//! Raster (image) laser engraving: grayscale power modulation or 1-bit Floyd-Steinberg dither.
//! Also the basis for depth-map style burns (darker = more power = deeper).
//!
//! Input pixels are 8-bit gray, row-major, top row first, 0 = black. The design-space origin is the
//! top-left of the image and Y grows downward (as everywhere in the design); output flips to the
//! machine's bottom-left origin like [`crate::laser::plan`].
use crate::error::{EngineError, Result};
use crate::laser::{Flavor, LaserJob, Machine};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RasterMode {
    /// Power follows darkness, quantised to 64 levels.
    Grayscale,
    /// Floyd-Steinberg to black/white; every dot burns at full power.
    Dither,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RasterSettings {
    /// Top-left of the image on the bed, mm (design space, Y down).
    pub x: f64,
    pub y: f64,
    pub width_mm: f64,
    pub height_mm: f64,
    /// Line spacing, mm.
    pub interval: f64,
    /// mm/s
    pub speed: f64,
    /// percent; white burns nothing, black burns `power_max`, `power_min` is the floor for any burn.
    pub power_min: f64,
    pub power_max: f64,
    pub bidirectional: bool,
    pub overscan: f64,
    pub invert: bool,
    pub mode: RasterMode,
}

const LEVELS: f64 = 63.0;

fn num(v: f64) -> String {
    let s = format!("{v:.3}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

/// Darkness in 0..=1 per pixel after optional invert (and dither).
fn darkness(gray: &[u8], w: usize, h: usize, invert: bool, mode: RasterMode) -> Vec<f32> {
    let mut d: Vec<f32> = gray.iter().map(|&g| if invert { g as f32 / 255.0 } else { 1.0 - g as f32 / 255.0 }).collect();
    if mode == RasterMode::Dither {
        for y in 0..h {
            for x in 0..w {
                let old = d[y * w + x];
                let new = if old >= 0.5 { 1.0 } else { 0.0 };
                d[y * w + x] = new;
                let err = old - new;
                let mut spread = |dx: isize, dy: usize, k: f32| {
                    let (nx, ny) = (x as isize + dx, y + dy);
                    if nx >= 0 && (nx as usize) < w && ny < h {
                        d[ny * w + nx as usize] += err * k;
                    }
                };
                spread(1, 0, 7.0 / 16.0);
                spread(-1, 1, 3.0 / 16.0);
                spread(0, 1, 5.0 / 16.0);
                spread(1, 1, 1.0 / 16.0);
            }
        }
    }
    d
}

pub fn plan_raster(gray: &[u8], width: u32, height: u32, s: &RasterSettings, m: &Machine) -> Result<LaserJob> {
    let (w, h) = (width as usize, height as usize);
    if w == 0 || h == 0 || gray.len() != w * h {
        return Err(EngineError::InvalidInput(format!("image is {w}x{h} but has {} pixels", gray.len())));
    }
    if s.width_mm <= 0.0 || s.height_mm <= 0.0 || s.interval <= 0.0 || s.speed <= 0.0 {
        return Err(EngineError::InvalidInput("size, interval and speed must be positive".into()));
    }
    let dark = darkness(gray, w, h, s.invert, s.mode);
    let on = match m.flavor {
        Flavor::GrblDynamic => "M4",
        Flavor::GrblConstant => "M3",
    };
    let feed = (s.speed * 60.0).max(1.0);
    let pitch = s.width_mm / w as f64;
    let power_at = |d: f32| -> i64 {
        if d <= 0.0 {
            return 0;
        }
        let q = if s.mode == RasterMode::Dither { 1.0 } else { (d as f64 * LEVELS).round() / LEVELS };
        if q <= 0.0 {
            return 0;
        }
        let pct = s.power_min + q * (s.power_max - s.power_min);
        (pct / 100.0 * m.s_max).round().clamp(0.0, m.s_max) as i64
    };

    let mut g = format!("(EmpuCAD raster {:?} {}x{} px)\nG21\nG90\n{on} S0\n", s.mode, w, h);
    let lines = (s.height_mm / s.interval).ceil().max(1.0) as usize;
    let (mut secs, mut pos_x) = (0.0, 0.0);
    let mut burned = 0usize;
    for li in 0..lines {
        let y_mm = ((li as f64 + 0.5) * s.interval).min(s.height_mm - 1e-9);
        let row = ((y_mm / s.height_mm) * h as f64).floor().clamp(0.0, h as f64 - 1.0) as usize;
        // runs of equal power along the row: (first_px, last_px_exclusive, S)
        let mut runs: Vec<(usize, usize, i64)> = Vec::new();
        for x in 0..w {
            let p = power_at(dark[row * w + x]);
            match runs.last_mut() {
                Some(r) if r.2 == p && r.1 == x => r.1 = x + 1,
                _ => runs.push((x, x + 1, p)),
            }
        }
        while runs.last().is_some_and(|r| r.2 == 0) {
            runs.pop();
        }
        let first_lit = runs.iter().position(|r| r.2 != 0);
        let Some(first_lit) = first_lit else { continue };
        runs.drain(..first_lit);
        burned += runs.iter().filter(|r| r.2 != 0).count();
        let reverse = s.bidirectional && li % 2 == 1;
        if reverse {
            runs.reverse();
        }
        let ym = m.bed_h - (s.y + y_mm);
        let xs = |px: usize| s.x + px as f64 * pitch;
        let (start_x, dir) = if reverse { (xs(runs[0].1), -1.0) } else { (xs(runs[0].0), 1.0) };
        let lead = start_x - dir * s.overscan;
        g.push_str(&format!("G0 X{} Y{}\n", num(lead), num(ym)));
        g.push_str(&format!("G1 X{} S0 F{}\n", num(start_x), num(feed)));
        let mut cx = start_x;
        for (a, b, p) in &runs {
            let end = if reverse { xs(*a) } else { xs(*b) };
            g.push_str(&format!("G1 X{} S{}\n", num(end), p));
            secs += (end - cx).abs() / s.speed;
            cx = end;
        }
        g.push_str(&format!("G1 X{} S0\n", num(cx + dir * s.overscan)));
        secs += s.overscan * 2.0 / s.speed + (pos_x - lead).abs() / (m.rapid / 60.0);
        pos_x = cx + dir * s.overscan;
    }
    g.push_str("M5\nS0\nG0 X0 Y0\nM2\n");
    if burned == 0 {
        return Err(EngineError::InvalidInput("image produces no burn (all white at this power)".into()));
    }
    Ok(LaserJob { gcode: g, seconds: secs })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> RasterSettings {
        RasterSettings {
            x: 10.0, y: 5.0, width_mm: 4.0, height_mm: 1.0, interval: 1.0, speed: 100.0,
            power_min: 0.0, power_max: 100.0, bidirectional: true, overscan: 0.0, invert: false, mode: RasterMode::Grayscale,
        }
    }
    fn machine() -> Machine {
        Machine { bed_h: 100.0, ..Default::default() }
    }

    #[test]
    fn white_is_skipped_and_black_burns_full_power_with_runs_merged() {
        // black, white, black, black
        let job = plan_raster(&[0, 255, 0, 0], 4, 1, &settings(), &machine()).unwrap();
        let g = &job.gcode;
        assert!(g.contains("G0 X10 Y94.5"), "{g}"); // y flipped: 100 - (5 + 0.5)
        assert!(g.contains("G1 X11 S1000"), "{g}");
        assert!(g.contains("G1 X12 S0"), "white gap burns nothing: {g}");
        assert!(g.contains("G1 X14 S1000"), "adjacent equal pixels merge into one run: {g}");
        assert_eq!(g.matches("S1000").count(), 2);
    }

    #[test]
    fn gray_scales_power_between_min_and_max() {
        let mut s = settings();
        s.power_min = 10.0;
        s.power_max = 50.0;
        let job = plan_raster(&[128, 128, 128, 128], 4, 1, &s, &machine()).unwrap();
        // darkness ~0.5 quantised to 31/63 -> 10 + 0.492*40 = 29.7% -> S297
        let s_val: i64 = job.gcode.split(" S").filter_map(|t| t.split_whitespace().next()?.parse().ok()).find(|&v: &i64| v > 0).unwrap();
        assert!((270..=320).contains(&s_val), "{s_val}");
    }

    #[test]
    fn invert_swaps_black_and_white() {
        let mut s = settings();
        s.invert = true;
        let job = plan_raster(&[0, 255, 255, 255], 4, 1, &s, &machine()).unwrap();
        assert!(job.gcode.contains("G0 X11 "), "first burn starts at the second pixel: {}", job.gcode);
    }

    #[test]
    fn odd_lines_run_right_to_left_when_bidirectional() {
        let mut s = settings();
        s.height_mm = 2.0;
        let job = plan_raster(&[0, 0, 0, 0, 0, 0, 0, 0], 4, 2, &s, &machine()).unwrap();
        let rapids: Vec<&str> = job.gcode.lines().filter(|l| l.starts_with("G0 X1")).collect();
        assert_eq!(rapids.len(), 2);
        assert!(rapids[0].starts_with("G0 X10 ") && rapids[1].starts_with("G0 X14 "), "{rapids:?}");
    }

    #[test]
    fn dither_burns_about_half_of_a_mid_gray_at_full_power_only() {
        let s = RasterSettings { width_mm: 100.0, height_mm: 1.0, mode: RasterMode::Dither, ..settings() };
        let job = plan_raster(&[128u8; 100], 100, 1, &s, &machine()).unwrap();
        let svals: Vec<i64> = job
            .gcode
            .lines()
            .filter(|l| l.starts_with("G1 X"))
            .filter_map(|l| l.split_whitespace().find_map(|t| t.strip_prefix('S')?.parse().ok()))
            .collect();
        assert!(svals.iter().all(|&v| v == 0 || v == 1000), "dither is 1-bit: {svals:?}");
        let lit = svals.iter().filter(|&&v| v == 1000).count();
        // 100 px of mid gray alternates: about half the pixels burn, as separate runs
        assert!((40..=60).contains(&lit), "lit runs: {lit}");
    }

    #[test]
    fn bad_input_is_rejected() {
        assert!(plan_raster(&[0, 0], 4, 1, &settings(), &machine()).is_err());
        assert!(plan_raster(&[255; 4], 4, 1, &settings(), &machine()).is_err(), "all white");
        let mut s = settings();
        s.interval = 0.0;
        assert!(plan_raster(&[0; 4], 4, 1, &s, &machine()).is_err());
    }
}
