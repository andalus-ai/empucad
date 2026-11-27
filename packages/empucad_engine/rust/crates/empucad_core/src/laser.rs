//! Laser job planning for GRBL-style controllers: layers, line vs fill, passes, power.
//! Coordinates in: millimetres, Y growing downward from the top-left of the bed (as in DabbleCAD).
//! Coordinates out: machine space, origin bottom-left, Y up.
use crate::geom2d::Region;
use crate::types::{Polyline, Pt};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LayerMode {
    Line,
    Fill,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LaserLayer {
    pub index: usize,
    pub mode: LayerMode,
    /// mm/s
    pub speed: f64,
    /// percent of the machine's S range
    pub power: f64,
    pub passes: u32,
    /// Fill line spacing, mm.
    pub interval: f64,
    /// Fill scan angle, degrees.
    pub angle: f64,
    pub bidirectional: bool,
    /// Extra run-out beyond each fill line (laser off), mm.
    pub overscan: f64,
}

impl LaserLayer {
    pub fn line(index: usize, speed: f64, power: f64) -> Self {
        Self { index, mode: LayerMode::Line, speed, power, passes: 1, interval: 0.1, angle: 0.0, bidirectional: true, overscan: 2.5 }
    }
    pub fn fill(index: usize, speed: f64, power: f64, interval: f64) -> Self {
        Self { mode: LayerMode::Fill, interval, ..Self::line(index, speed, power) }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flavor {
    /// `M4`: power follows speed (recommended for engraving).
    GrblDynamic,
    /// `M3`: constant power.
    GrblConstant,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Machine {
    pub bed_w: f64,
    pub bed_h: f64,
    pub s_max: f64,
    /// mm/min
    pub rapid: f64,
    pub flavor: Flavor,
}

impl Default for Machine {
    fn default() -> Self {
        Self { bed_w: 400.0, bed_h: 400.0, s_max: 1000.0, rapid: 6000.0, flavor: Flavor::GrblDynamic }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct LaserShape {
    pub layer: usize,
    pub outlines: Vec<Polyline>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct LaserJob {
    pub gcode: String,
    pub seconds: f64,
}

/// Horizontal scan lines across `region` rotated by `angle_deg`; returns segments in region space.
pub fn scan_fill(region: &Region, interval: f64, angle_deg: f64, bidirectional: bool) -> Vec<(Pt, Pt)> {
    let Some(_) = region.bounds() else { return vec![] };
    let a = angle_deg.to_radians();
    let (c, s) = (a.cos(), a.sin());
    let rot = |p: Pt, c: f64, s: f64| [p[0] * c - p[1] * s, p[0] * s + p[1] * c];
    // rotate the polygon by -angle so scan lines become horizontal
    let rings: Vec<Vec<Pt>> = region.rings().into_iter().map(|(r, _)| r.into_iter().map(|p| rot(p, c, -s)).collect()).collect();
    let (mut lo, mut hi) = (f64::MAX, f64::MIN);
    for p in rings.iter().flatten() {
        lo = lo.min(p[1]);
        hi = hi.max(p[1]);
    }
    let interval = interval.max(1e-3);
    let mut out = Vec::new();
    let mut y = lo + interval / 2.0;
    let mut flip = false;
    while y < hi {
        let mut xs = Vec::new();
        for r in &rings {
            for i in 0..r.len() {
                let (a, b) = (r[i], r[(i + 1) % r.len()]);
                if (a[1] > y) != (b[1] > y) {
                    xs.push(a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
                }
            }
        }
        xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        for pair in xs.chunks_exact(2) {
            let (p, q) = (rot([pair[0], y], c, s), rot([pair[1], y], c, s));
            out.push(if bidirectional && flip { (q, p) } else { (p, q) });
        }
        if bidirectional {
            flip = !flip;
        }
        y += interval;
    }
    out
}

/// Parse laser G-code into drawable moves: flat `x, y, power, rapid(1|0)` per move (mm, machine space).
///
/// Understands modal `G0`/`G1`, `X`/`Y` words, modal `S`, `M3`/`M4`/`M5`, `G90` (absolute only) and
/// strips `(...)` and `;` comments. `power` is the S value in effect for the move, or 0 when the laser
/// is off (`M5`) or the move is a rapid. Unknown words are ignored.
pub fn preview_gcode(gcode: &str) -> Vec<f32> {
    let (mut x, mut y, mut s) = (0.0f64, 0.0f64, 0.0f64);
    let (mut rapid, mut laser_on) = (true, false);
    let mut out = Vec::new();
    for raw in gcode.lines() {
        let mut line = String::new();
        let mut depth = 0;
        for ch in raw.chars() {
            match ch {
                '(' => depth += 1,
                ')' => depth = (depth - 1).max(0),
                ';' if depth == 0 => break,
                c if depth == 0 => line.push(c),
                _ => {}
            }
        }
        let (mut nx, mut ny, mut moved) = (x, y, false);
        for w in line.split_whitespace() {
            let (letter, rest) = w.split_at(1);
            let Ok(v) = rest.parse::<f64>() else { continue };
            match letter.to_ascii_uppercase().as_str() {
                "G" if v == 0.0 => rapid = true,
                "G" if v == 1.0 => rapid = false,
                "M" if v == 3.0 || v == 4.0 => laser_on = true,
                "M" if v == 5.0 || v == 2.0 || v == 30.0 => laser_on = false,
                "S" => s = v,
                "X" => {
                    nx = v;
                    moved = true;
                }
                "Y" => {
                    ny = v;
                    moved = true;
                }
                _ => {}
            }
        }
        if moved {
            let power = if rapid || !laser_on { 0.0 } else { s };
            out.extend_from_slice(&[nx as f32, ny as f32, power as f32, if rapid { 1.0 } else { 0.0 }]);
            x = nx;
            y = ny;
        }
    }
    out
}

fn num(v: f64) -> String {
    let s = format!("{v:.3}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

/// Plan every used layer in index order and emit GRBL G-code.
pub fn plan(shapes: &[LaserShape], layers: &[LaserLayer], m: &Machine) -> LaserJob {
    let fy = |y: f64| m.bed_h - y;
    let on = match m.flavor {
        Flavor::GrblDynamic => "M4",
        Flavor::GrblConstant => "M3",
    };
    let mut g = String::from("(EmpuCAD laser)\nG21\nG90\n");
    g.push_str(&format!("{on} S0\n"));
    let mut secs = 0.0;
    let mut pos: Pt = [0.0, 0.0];
    let mut used: Vec<usize> = shapes.iter().map(|s| s.layer).collect();
    used.sort_unstable();
    used.dedup();
    for li in used {
        let Some(layer) = layers.iter().find(|l| l.index == li) else { continue };
        let s_val = (layer.power / 100.0 * m.s_max).round().clamp(0.0, m.s_max) as i64;
        let feed = (layer.speed * 60.0).max(1.0);
        g.push_str(&format!("(layer {:02} {:?} {} mm/s {}%)\n", li, layer.mode, num(layer.speed), num(layer.power)));
        let layer_shapes: Vec<&LaserShape> = shapes.iter().filter(|s| s.layer == li).collect();
        let outlines: Vec<Polyline> = layer_shapes.iter().flat_map(|s| s.outlines.clone()).collect();
        let mut jobs: Vec<Vec<Pt>> = Vec::new(); // each is a polyline to burn with power on
        let mut overscan_dirs: Vec<Option<(Pt, Pt)>> = Vec::new();
        match layer.mode {
            LayerMode::Line => {
                for p in &outlines {
                    let mut pts = p.pts.clone();
                    if p.closed && !pts.is_empty() {
                        pts.push(pts[0]);
                    }
                    jobs.push(pts);
                    overscan_dirs.push(None);
                }
            }
            LayerMode::Fill => {
                // one region per design shape (even-odd inside it), then union: overlapping shapes merge
                let region = layer_shapes.iter().fold(Region::default(), |acc, sh| acc.union(&Region::from_outlines(&sh.outlines)));
                for (a, b) in scan_fill(&region, layer.interval, layer.angle, layer.bidirectional) {
                    jobs.push(vec![a, b]);
                    overscan_dirs.push(Some((a, b)));
                }
            }
        }
        for _pass in 0..layer.passes.max(1) {
            for (pts, os) in jobs.iter().zip(&overscan_dirs) {
                if pts.len() < 2 {
                    continue;
                }
                let mut start = pts[0];
                let mut end = *pts.last().unwrap();
                if let Some((a, b)) = os {
                    let len = (b[0] - a[0]).hypot(b[1] - a[1]).max(1e-9);
                    let d = [(b[0] - a[0]) / len, (b[1] - a[1]) / len];
                    start = [a[0] - d[0] * layer.overscan, a[1] - d[1] * layer.overscan];
                    end = [b[0] + d[0] * layer.overscan, b[1] + d[1] * layer.overscan];
                    g.push_str(&format!("G0 X{} Y{}\nG1 X{} Y{} S0 F{}\n", num(start[0]), num(fy(start[1])), num(a[0]), num(fy(a[1])), num(feed)));
                    g.push_str(&format!("G1 X{} Y{} S{}\n", num(b[0]), num(fy(b[1])), s_val));
                    g.push_str(&format!("G1 X{} Y{} S0\n", num(end[0]), num(fy(end[1]))));
                    secs += ((end[0] - start[0]).hypot(end[1] - start[1])) / layer.speed.max(1e-6)
                        + (pos[0] - start[0]).hypot(pos[1] - start[1]) / (m.rapid / 60.0);
                    pos = end;
                    continue;
                }
                g.push_str(&format!("G0 X{} Y{}\n", num(start[0]), num(fy(start[1]))));
                g.push_str(&format!("G1 X{} Y{} S{} F{}\n", num(pts[1][0]), num(fy(pts[1][1])), s_val, num(feed)));
                for p in &pts[2..] {
                    g.push_str(&format!("G1 X{} Y{}\n", num(p[0]), num(fy(p[1]))));
                }
                g.push_str("S0\n");
                let len: f64 = pts.windows(2).map(|w| (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1])).sum();
                secs += len / layer.speed.max(1e-6) + (pos[0] - start[0]).hypot(pos[1] - start[1]) / (m.rapid / 60.0);
                pos = end;
            }
        }
    }
    g.push_str("M5\nS0\nG0 X0 Y0\nM2\n");
    LaserJob { gcode: g, seconds: secs }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sq(x: f64, y: f64, s: f64) -> Polyline {
        Polyline::closed(vec![[x, y], [x + s, y], [x + s, y + s], [x, y + s]])
    }

    #[test]
    fn preview_reads_back_what_plan_writes() {
        let layers = vec![LaserLayer::line(0, 10.0, 50.0)];
        let job = plan(&[LaserShape { layer: 0, outlines: vec![sq(10., 10., 20.)] }], &layers, &Machine { bed_h: 100.0, ..Default::default() });
        let mv = preview_gcode(&job.gcode);
        assert_eq!(mv.len() % 4, 0);
        let moves: Vec<&[f32]> = mv.chunks_exact(4).collect();
        // first move is the rapid to the start of the square (10, 90), laser off
        assert_eq!((moves[0][0], moves[0][1], moves[0][2], moves[0][3]), (10.0, 90.0, 0.0, 1.0));
        // the four sides burn at S500
        let burns: Vec<_> = moves.iter().filter(|m| m[2] == 500.0 && m[3] == 0.0).collect();
        assert_eq!(burns.len(), 4);
        // total burned length = perimeter 80 mm
        let mut len = 0.0f32;
        for w in moves.windows(2) {
            if w[1][2] > 0.0 {
                len += (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]);
            }
        }
        assert!((len - 80.0).abs() < 1e-3, "{len}");
    }

    #[test]
    fn preview_ignores_comments_and_resets_power_on_m5() {
        let mv = preview_gcode("(layer 00 Line)\nG21 ; units\nM4 S0\nG0 X1 Y2\nG1 X5 Y2 S700 F600\nM5\nG1 X9 Y2\n");
        assert_eq!(mv, vec![1., 2., 0., 1., 5., 2., 700., 0., 9., 2., 0., 0.]);
        assert!(preview_gcode("").is_empty());
        assert!(preview_gcode("G1 Xabc Y").is_empty());
    }

    #[test]
    fn scan_fill_covers_a_square_and_alternates_direction() {
        let r = Region::from_outlines(&[sq(0., 0., 10.)]);
        let lines = scan_fill(&r, 1.0, 0.0, true);
        assert_eq!(lines.len(), 10);
        assert!(lines[0].0[0] < lines[0].1[0]);
        assert!(lines[1].0[0] > lines[1].1[0]);
        assert!(lines.iter().all(|(a, b)| ((a[0] - b[0]).abs() - 10.0).abs() < 1e-9));
    }

    #[test]
    fn scan_fill_respects_holes() {
        let r = Region::from_outlines(&[sq(0., 0., 10.), sq(3., 3., 4.)]);
        let lines = scan_fill(&r, 1.0, 0.0, false);
        // rows crossing the hole are split in two segments
        assert!(lines.len() > 10);
        let total: f64 = lines.iter().map(|(a, b)| (b[0] - a[0]).abs()).sum();
        assert!((total - (100.0 - 16.0)).abs() < 1e-6, "{total}");
    }

    #[test]
    fn grbl_line_job_flips_y_sets_power_and_ends_safely() {
        let layers = vec![LaserLayer::line(0, 10.0, 50.0)];
        let job = plan(&[LaserShape { layer: 0, outlines: vec![sq(10., 10., 20.)] }], &layers, &Machine { bed_h: 100.0, ..Default::default() });
        assert!(job.gcode.contains("M4 S0"));
        assert!(job.gcode.contains("G0 X10 Y90"), "y must flip: {}", job.gcode);
        assert!(job.gcode.contains("S500 F600"));
        assert!(job.gcode.trim_end().ends_with("M2"));
        assert!((job.seconds - 8.0).abs() < 1.5, "80 mm at 10 mm/s ~ 8 s, got {}", job.seconds);
    }

    #[test]
    fn passes_repeat_and_constant_power_uses_m3() {
        let mut l = LaserLayer::line(0, 20.0, 100.0);
        l.passes = 3;
        let m = Machine { flavor: Flavor::GrblConstant, ..Default::default() };
        let job = plan(&[LaserShape { layer: 0, outlines: vec![sq(0., 0., 5.)] }], &[l], &m);
        assert_eq!(job.gcode.matches("S1000 F1200").count(), 3);
        assert!(job.gcode.contains("M3 S0"));
    }

    #[test]
    fn overlapping_fill_shapes_merge_instead_of_cancelling() {
        let layers = vec![LaserLayer { overscan: 0.0, ..LaserLayer::fill(0, 100.0, 50.0, 1.0) }];
        let shapes = [
            LaserShape { layer: 0, outlines: vec![sq(0., 0., 10.)] },
            LaserShape { layer: 0, outlines: vec![sq(5., 0., 10.)] }, // overlaps the first by 5 mm
        ];
        let job = plan(&shapes, &layers, &Machine::default());
        let mv = preview_gcode(&job.gcode);
        let mut burned = 0.0f32;
        for w in mv.chunks_exact(4).collect::<Vec<_>>().windows(2) {
            if w[1][2] > 0.0 {
                burned += (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]);
            }
        }
        // union is 15 x 10 mm: ten 15 mm rows. If the overlap were XOR'd out this would be 100.
        assert!((burned - 150.0).abs() < 1e-3, "burned {burned} mm");
    }

    #[test]
    fn fill_uses_overscan_with_laser_off() {
        let layers = vec![LaserLayer::fill(0, 100.0, 30.0, 1.0)];
        let job = plan(&[LaserShape { layer: 0, outlines: vec![sq(10., 10., 3.)] }], &layers, &Machine::default());
        assert!(job.gcode.contains("S0 F6000"));
        assert!(job.gcode.contains(" S300\n"));
        assert!(job.gcode.contains("G0 X7.5"), "2.5 mm overscan before x=10:\n{}", job.gcode);
    }
}
