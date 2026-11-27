//! G-code checker: parses program text (not the generator's data structures) and replays it.
//!
//! Handles modal `G0`/`G1`/`G2`/`G3` (arcs with `I`/`J`), `G90`/`G91`, `G20`/`G21`, `G4`, `F`, `M3`/`M4`/`M5`,
//! `N` line numbers and `(...)` / `;` comments. Z = 0 is the top of the stock and cuts are negative.
//!
//! Because it reads only the text, running it over generated programs is an independent test of the
//! generator, and the same check protects users from any future bug.
use super::arcs;

#[derive(Clone, Debug, Default)]
pub struct Limits {
    /// Deepest the tool may go below the stock top (positive mm). `None` = unchecked.
    pub stock_thickness: Option<f64>,
    /// Machine travel in X and Y as (min, max) mm. `None` = unchecked.
    pub x_range: Option<(f64, f64)>,
    pub y_range: Option<(f64, f64)>,
    /// Rapid rate for the time estimate, mm/min (default 3000).
    pub rapid_rate: Option<f64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IssueKind {
    /// A `G0` that plunges into the stock or travels sideways inside it.
    RapidIntoMaterial,
    DepthExceeded,
    OutOfTravel,
    /// Cutting below the surface with the spindle off.
    SpindleOff,
    /// A feed move before any `F` word.
    NoFeed,
    /// `G2`/`G3` whose start and end are not the same distance from the centre.
    ArcRadius,
    /// Motion before `G20`/`G21`.
    NoUnits,
    /// A word this checker does not understand (arcs with `R`, other planes, cutter compensation, ...).
    Unsupported,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Issue {
    /// 1-based line in the program text.
    pub line: usize,
    pub kind: IssueKind,
    pub message: String,
}

#[derive(Clone, Debug, Default)]
pub struct Report {
    pub issues: Vec<Issue>,
    pub bounds_min: [f64; 3],
    pub bounds_max: [f64; 3],
    pub cut_length: f64,
    pub rapid_length: f64,
    pub seconds: f64,
    pub moves: usize,
}

const EPS: f64 = 1e-6;
/// Output rounding (inch programs print 0.0001 in = 2.5 micron) must not raise false depth alarms.
const DEPTH_TOLERANCE: f64 = 0.005;

fn strip_comments(raw: &str) -> String {
    let mut out = String::new();
    let mut depth = 0;
    for ch in raw.chars() {
        match ch {
            '(' => depth += 1,
            ')' => depth = (depth - 1).max(0),
            ';' if depth == 0 => break,
            c if depth == 0 => out.push(c),
            _ => {}
        }
    }
    out
}

pub fn analyze(gcode: &str, limits: &Limits) -> Report {
    let mut r = Report { bounds_min: [f64::MAX; 3], bounds_max: [f64::MIN; 3], ..Default::default() };
    let rapid_rate = limits.rapid_rate.unwrap_or(3000.0);
    let (mut mode, mut abs, mut scale) = (0u8, true, 1.0f64);
    let mut units_set = false;
    let mut units_warned = false;
    let (mut feed, mut spindle) = (0.0f64, false);
    // The machine is assumed to start at the XY origin (the same convention the generator's time
    // estimate uses); Z is unknown until the first move sets it.
    let mut pos = [0.0, 0.0, f64::NAN];
    let note = |r: &mut Report, line: usize, kind: IssueKind, msg: String| r.issues.push(Issue { line, kind, message: msg });

    for (ln, raw) in gcode.lines().enumerate() {
        let line_no = ln + 1;
        let text = strip_comments(raw);
        let (mut x, mut y, mut z, mut i, mut j) = (None, None, None, None::<f64>, None::<f64>);
        let mut has_r = false;
        let mut dwell = None;
        let mut motion_this_line = false;
        for w in text.split_whitespace() {
            let mut cs = w.chars();
            let Some(letter) = cs.next() else { continue };
            let Ok(v) = cs.as_str().parse::<f64>() else { continue };
            match letter.to_ascii_uppercase() {
                'N' => {}
                'G' => match v as i64 {
                    0 => {
                        mode = 0;
                        motion_this_line = true;
                    }
                    1 => {
                        mode = 1;
                        motion_this_line = true;
                    }
                    2 => {
                        mode = 2;
                        motion_this_line = true;
                    }
                    3 => {
                        mode = 3;
                        motion_this_line = true;
                    }
                    4 => {}
                    20 => {
                        scale = 25.4;
                        units_set = true;
                    }
                    21 => {
                        scale = 1.0;
                        units_set = true;
                    }
                    90 => abs = true,
                    91 => abs = false,
                    17 | 40 | 49 | 54..=59 | 61 | 64 | 80 | 94 => {}
                    18 | 19 => note(&mut r, line_no, IssueKind::Unsupported, format!("plane G{} is not supported; arcs are checked in XY only", v as i64)),
                    41 | 42 => note(&mut r, line_no, IssueKind::Unsupported, format!("cutter compensation G{} is not supported", v as i64)),
                    other => note(&mut r, line_no, IssueKind::Unsupported, format!("G{other} is not understood by the checker")),
                },
                'M' => match v as i64 {
                    3 | 4 => spindle = true,
                    5 | 2 | 30 => spindle = false,
                    _ => {}
                },
                'F' => feed = v * scale,
                'X' => x = Some(v * scale),
                'Y' => y = Some(v * scale),
                'Z' => z = Some(v * scale),
                'I' => i = Some(v * scale),
                'J' => j = Some(v * scale),
                'R' => has_r = true,
                'P' => dwell = Some(v),
                _ => {}
            }
        }
        // G4 P<seconds> (our posts use seconds)
        if text.split_whitespace().any(|w| w.eq_ignore_ascii_case("G4")) {
            if let Some(p) = dwell {
                r.seconds += p;
            }
            continue;
        }
        if x.is_none() && y.is_none() && z.is_none() {
            continue;
        }
        if !motion_this_line && !(0..=3).contains(&mode) {
            continue;
        }
        if !units_set && !units_warned {
            units_warned = true;
            note(&mut r, line_no, IssueKind::NoUnits, "motion before G20/G21; millimetres assumed".into());
        }
        // Incremental moves need a Z anchor too: an unknown axis is taken to be the origin.
        let start = if abs { pos } else { pos.map(|c| if c.is_finite() { c } else { 0.0 }) };
        let target = [
            x.map(|v| if abs { v } else { start[0] + v }).unwrap_or(start[0]),
            y.map(|v| if abs { v } else { start[1] + v }).unwrap_or(start[1]),
            z.map(|v| if abs { v } else { start[2] + v }).unwrap_or(start[2]),
        ];
        let known = start.iter().all(|c| c.is_finite());
        r.moves += 1;

        // ---- geometry: length of this move, and arc validation
        let mut length = 0.0;
        if known {
            length = ((target[0] - start[0]).powi(2) + (target[1] - start[1]).powi(2) + (target[2] - start[2]).powi(2)).sqrt();
            if mode == 2 || mode == 3 {
                if has_r {
                    note(&mut r, line_no, IssueKind::Unsupported, "arcs given with R are not supported (use I/J)".into());
                } else if let (Some(ci), Some(cj)) = (i, j) {
                    let c = [start[0] + ci, start[1] + cj];
                    let (r0, r1) = ((start[0] - c[0]).hypot(start[1] - c[1]), (target[0] - c[0]).hypot(target[1] - c[1]));
                    if (r0 - r1).abs() > 0.01 {
                        note(&mut r, line_no, IssueKind::ArcRadius, format!("arc start radius {r0:.3} and end radius {r1:.3} differ"));
                    }
                    let pts = arcs::sample([start[0], start[1]], [target[0], target[1]], c, mode == 2, 1.0);
                    let mut prev = [start[0], start[1]];
                    let mut planar = 0.0;
                    for p in pts {
                        planar += (p[0] - prev[0]).hypot(p[1] - prev[1]);
                        prev = p;
                    }
                    length = planar.hypot(target[2] - start[2]);
                } else {
                    note(&mut r, line_no, IssueKind::Unsupported, "arc without I and J".into());
                }
            }
        }

        // ---- safety rules
        if mode == 0 {
            let xy_changes = known && ((target[0] - start[0]).abs() > EPS || (target[1] - start[1]).abs() > EPS);
            let start_below = known && start[2] < -EPS;
            if target[2] < -EPS || (start_below && xy_changes) {
                note(&mut r, line_no, IssueKind::RapidIntoMaterial, format!("rapid move at Z {:.3} into or inside the stock", target[2]));
            }
        } else {
            if target[2] < -EPS && !spindle {
                note(&mut r, line_no, IssueKind::SpindleOff, "cutting below the surface with the spindle off".into());
            }
            if feed <= 0.0 {
                note(&mut r, line_no, IssueKind::NoFeed, "feed move before any F word".into());
                feed = f64::MIN_POSITIVE; // report once per move, not NaN time
            }
        }
        if let Some(t) = limits.stock_thickness {
            if target[2] < -t - DEPTH_TOLERANCE {
                note(&mut r, line_no, IssueKind::DepthExceeded, format!("Z {:.3} is deeper than the {t:.3} mm stock", target[2]));
            }
        }
        if let Some((lo, hi)) = limits.x_range {
            if target[0] < lo - 1e-6 || target[0] > hi + 1e-6 {
                note(&mut r, line_no, IssueKind::OutOfTravel, format!("X {:.3} is outside the travel {lo}..{hi}", target[0]));
            }
        }
        if let Some((lo, hi)) = limits.y_range {
            if target[1] < lo - 1e-6 || target[1] > hi + 1e-6 {
                note(&mut r, line_no, IssueKind::OutOfTravel, format!("Y {:.3} is outside the travel {lo}..{hi}", target[1]));
            }
        }

        // ---- totals
        if known {
            if mode == 0 {
                r.rapid_length += length;
                r.seconds += length / rapid_rate * 60.0;
            } else {
                r.cut_length += length;
                r.seconds += length / feed.max(1e-9) * 60.0;
            }
        }
        for (k, &t) in target.iter().enumerate() {
            if t.is_finite() {
                r.bounds_min[k] = r.bounds_min[k].min(t);
                r.bounds_max[k] = r.bounds_max[k].max(t);
            }
        }
        pos = target;
    }
    if r.moves == 0 {
        r.bounds_min = [0.0; 3];
        r.bounds_max = [0.0; 3];
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(r: &Report) -> Vec<IssueKind> {
        r.issues.iter().map(|i| i.kind).collect()
    }

    const OK: &str = "G21\nG90\nM3 S10000\nG4 P3\nG0 Z5\nG0 X10 Y10\nG0 Z1\nG1 Z-1 F200\nG1 X30 F600\nG1 Y30\nG0 Z5\nM5\nM30\n";

    #[test]
    fn a_clean_program_has_no_issues_and_sensible_totals() {
        let r = analyze(OK, &Limits::default());
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert_eq!(r.bounds_max, [30.0, 30.0, 5.0]);
        assert_eq!(r.bounds_min[2], -1.0);
        assert!((r.cut_length - (2.0 + 20.0 + 20.0)).abs() < 1e-9, "plunge 1 -> -1 is 2 mm: {}", r.cut_length);
        // 3 s dwell + cuts (1/200 + 40/600) min + rapids
        assert!(r.seconds > 3.0 + 4.0 && r.seconds < 3.0 + 8.0, "{}", r.seconds);
    }

    #[test]
    fn comments_line_numbers_and_inline_words_are_handled() {
        let p = "(header)\nN10 G21 ; units\nN20 G90\nN30 M3 S100\nN40 G0 Z5\nN50 G1 X5 (go) Z-1 F300\n";
        let r = analyze(p, &Limits::default());
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert_eq!(r.moves, 2);
    }

    #[test]
    fn incremental_mode_and_inches() {
        let r = analyze("G20\nG91\nM3\nG0 Z0.2\nG1 X1 F10\nG1 Y1\n", &Limits::default());
        assert!(r.issues.is_empty(), "{:?}", r.issues);
        assert!((r.bounds_max[0] - 25.4).abs() < 1e-9 && (r.bounds_max[1] - 25.4).abs() < 1e-9, "{:?}", r.bounds_max);
        assert!((r.cut_length - 50.8).abs() < 1e-9);
    }

    #[test]
    fn arcs_measure_their_length_and_mismatched_radii_are_caught() {
        let ok = analyze("G21\nM3\nG0 Z5\nG0 X10 Y0\nG1 Z-1 F100\nG3 X0 Y10 I-10 J0 F200\n", &Limits::default());
        assert!(ok.issues.is_empty(), "{:?}", ok.issues);
        let arc_len = 10.0 * std::f64::consts::FRAC_PI_2;
        assert!((ok.cut_length - (6.0 + arc_len)).abs() < 0.01, "6 mm plunge (5 -> -1) plus the arc: {}", ok.cut_length);
        let bad = analyze("G21\nM3\nG0 Z5\nG0 X10 Y0\nG1 Z-1 F100\nG3 X0 Y11 I-10 J0 F200\n", &Limits::default());
        assert_eq!(kinds(&bad), vec![IssueKind::ArcRadius]);
        // clockwise goes the long way round: three quarters of the circle
        let cw = analyze("G21\nM3\nG0 Z5\nG0 X10 Y0\nG1 Z-1 F100\nG2 X0 Y10 I-10 J0 F200\n", &Limits::default());
        assert!((cw.cut_length - (6.0 + 3.0 * arc_len)).abs() < 0.05, "{}", cw.cut_length);
    }

    #[test]
    fn rapids_into_or_inside_the_stock_are_flagged_but_a_retract_is_not() {
        assert_eq!(kinds(&analyze("G21\nG0 Z5\nG0 X0 Y0\nG0 Z-2\n", &Limits::default())), vec![IssueKind::RapidIntoMaterial]);
        let sideways = analyze("G21\nM3\nG0 Z5\nG1 Z-1 F100\nG0 X10\n", &Limits::default());
        assert_eq!(kinds(&sideways), vec![IssueKind::RapidIntoMaterial]);
        assert!(analyze("G21\nM3\nG0 Z5\nG1 Z-1 F100\nG0 Z5\n", &Limits::default()).issues.is_empty(), "straight-up retract is fine");
    }

    #[test]
    fn depth_travel_spindle_and_feed_rules() {
        let lim = Limits { stock_thickness: Some(3.0), x_range: Some((0.0, 100.0)), y_range: Some((0.0, 100.0)), rapid_rate: None };
        assert_eq!(kinds(&analyze("G21\nM3\nG1 Z-3.5 F100\n", &lim)), vec![IssueKind::DepthExceeded]);
        assert!(analyze("G21\nM3\nG1 Z-3 F100\n", &lim).issues.is_empty(), "exactly the stock thickness is allowed");
        assert_eq!(kinds(&analyze("G21\nM3\nG0 Z5\nG0 X101\n", &lim)), vec![IssueKind::OutOfTravel]);
        assert_eq!(kinds(&analyze("G21\nG1 Z-1 F100\n", &lim)), vec![IssueKind::SpindleOff]);
        assert_eq!(kinds(&analyze("G21\nM3\nG1 Z-1\n", &lim)), vec![IssueKind::NoFeed]);
        assert!(analyze("G21\nG1 Z1 F100\n", &lim).issues.is_empty(), "air moves with the spindle off are fine");
    }

    #[test]
    fn unsupported_and_unitless_programs_are_reported_not_crashed_on() {
        let r = analyze("G0 X1\nG18\nG41\nG2 X1 Y1 R5\n", &Limits::default());
        assert!(kinds(&r).contains(&IssueKind::NoUnits));
        assert!(kinds(&r).iter().filter(|k| **k == IssueKind::Unsupported).count() >= 2);
        assert_eq!(analyze("", &Limits::default()).moves, 0);
        assert!(analyze("garbage Xabc G\n???\n", &Limits::default()).issues.is_empty());
    }

    #[test]
    fn issues_carry_the_line_number() {
        let r = analyze("G21\nM3\nG0 Z5\n\nG0 Z-2\n", &Limits::default());
        assert_eq!(r.issues[0].line, 5);
    }
}
