//! From toolpaths to machine moves and G-code text.
//!
//! [`expand_moves`] is the single source of truth for motion: the writer, the time estimate and any
//! simulator all consume its output.
mod arcs;
mod post;
mod writer;

pub use arcs::{fit as fit_arcs, Seg};
pub use post::{Post, ToolChange, POSTS};
pub use writer::write;

use crate::types::Path3;

#[derive(Clone, Debug, PartialEq)]
pub struct Section {
    pub name: String,
    pub tool_number: u32,
    pub feed: f64,
    pub plunge: f64,
    pub rpm: f64,
    pub paths: Vec<Path3>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Program {
    pub sections: Vec<Section>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Output {
    pub post: &'static Post,
    pub inches: bool,
    pub safe_z: f64,
    pub clear_z: f64,
    pub rapid_rate: f64,
    pub spin_up_secs: f64,
    /// Fit `G2`/`G3` arcs to runs of short cuts (smaller, smoother programs). Off by default.
    pub arcs: bool,
    /// Largest distance from the original path an arc may stray, mm.
    pub arc_tolerance: f64,
}

impl Output {
    pub fn new(post: &'static Post) -> Self {
        Self { post, inches: false, safe_z: 5.0, clear_z: 1.0, rapid_rate: 3000.0, spin_up_secs: 3.0, arcs: false, arc_tolerance: 0.005 }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    Section(usize),
    /// `None` coordinates are left unchanged (used for the very first retract).
    Move { x: Option<f64>, y: Option<f64>, z: f64, rapid: bool, feed: f64 },
    /// Planar arc at constant Z. `i`,`j` = centre relative to the start; `len` = arc length in mm.
    Arc { x: f64, y: f64, z: f64, i: f64, j: f64, cw: bool, len: f64, feed: f64 },
}

const EPS: f64 = 1e-6;

pub fn expand_moves(program: &Program, o: &Output) -> Vec<Event> {
    let mut ev = Vec::new();
    let mut pos: Option<[f64; 3]> = None;
    let mv = |ev: &mut Vec<Event>, pos: &mut Option<[f64; 3]>, x: f64, y: f64, z: f64, rapid: bool, feed: f64| {
        if let Some(p) = pos {
            if (p[0] - x).abs() < EPS && (p[1] - y).abs() < EPS && (p[2] - z).abs() < EPS {
                return;
            }
        }
        ev.push(Event::Move { x: Some(x), y: Some(y), z, rapid, feed });
        *pos = Some([x, y, z]);
    };
    for (s, sec) in program.sections.iter().enumerate() {
        ev.push(Event::Section(s));
        let feed = sec.feed.max(1.0);
        let plunge = if sec.plunge > 0.0 { sec.plunge } else { feed / 3.0 };
        // Never descend faster than the plunge rate: limit the feed on steep segments.
        let cut_feed = |a: [f64; 3], b: [f64; 3]| {
            let h = (b[0] - a[0]).hypot(b[1] - a[1]);
            let dz = b[2] - a[2];
            if dz >= -1e-9 {
                feed
            } else if h < 1e-9 {
                plunge
            } else {
                feed.min(plunge * h.hypot(dz) / -dz)
            }
        };
        for path in &sec.paths {
            let Some(&first) = path.pts.first() else { continue };
            match pos {
                Some(p) if path.link && p[2] < o.clear_z && !p[0].is_nan() => {
                    mv(&mut ev, &mut pos, first[0], first[1], first[2], false, cut_feed(p, first));
                }
                _ => {
                    match pos {
                        None => {
                            ev.push(Event::Move { x: None, y: None, z: o.safe_z, rapid: true, feed: 0.0 });
                            pos = Some([f64::NAN, f64::NAN, o.safe_z]);
                        }
                        Some(p) if p[2] < o.safe_z => mv(&mut ev, &mut pos, p[0], p[1], o.safe_z, true, 0.0),
                        _ => {}
                    }
                    mv(&mut ev, &mut pos, first[0], first[1], o.safe_z, true, 0.0);
                    let stop = o.safe_z.min(first[2].max(0.0) + o.clear_z);
                    if stop < o.safe_z - 1e-9 {
                        mv(&mut ev, &mut pos, first[0], first[1], stop, true, 0.0);
                    }
                    if first[2] < stop - 1e-9 {
                        mv(&mut ev, &mut pos, first[0], first[1], first[2], false, plunge);
                    }
                }
            }
            if o.arcs {
                let mut cur = path.pts[0];
                for seg in arcs::fit(&path.pts, o.arc_tolerance) {
                    match seg {
                        Seg::Line(to) => {
                            mv(&mut ev, &mut pos, to[0], to[1], to[2], false, cut_feed(cur, to));
                            cur = to;
                        }
                        Seg::Arc { to, i, j, cw, len } => {
                            ev.push(Event::Arc { x: to[0], y: to[1], z: to[2], i, j, cw, len, feed });
                            pos = Some(to);
                            cur = to;
                        }
                    }
                }
            } else {
                for w in path.pts.windows(2) {
                    mv(&mut ev, &mut pos, w[1][0], w[1][1], w[1][2], false, cut_feed(w[0], w[1]));
                }
            }
        }
    }
    if let Some(p) = pos {
        if p[2] < o.safe_z {
            ev.push(Event::Move { x: Some(p[0]), y: Some(p[1]), z: o.safe_z, rapid: true, feed: 0.0 });
        }
    }
    ev
}

/// Flat preview for a viewer: x, y, z, rapid(1.0/0.0) per move, in job coordinates (mm).
pub fn preview(program: &Program, o: &Output) -> Vec<f32> {
    let mut out = Vec::new();
    let mut pos = [0.0f64; 3];
    for e in expand_moves(program, o) {
        match e {
            Event::Move { x, y, z, rapid, .. } => {
                pos = [x.unwrap_or(pos[0]), y.unwrap_or(pos[1]), z];
                out.extend_from_slice(&[pos[0] as f32, pos[1] as f32, pos[2] as f32, if rapid { 1.0 } else { 0.0 }]);
            }
            Event::Arc { x, y, z, i, j, cw, .. } => {
                let centre = [pos[0] + i, pos[1] + j];
                for p in arcs::sample([pos[0], pos[1]], [x, y], centre, cw, 4.0) {
                    out.extend_from_slice(&[p[0] as f32, p[1] as f32, z as f32, 0.0]);
                }
                pos = [x, y, z];
            }
            Event::Section(_) => {}
        }
    }
    out
}

/// Estimated run time in seconds (moves + spindle spin-up per section).
pub fn estimate_seconds(program: &Program, o: &Output) -> f64 {
    let mut secs = 0.0;
    let mut pos: Option<[f64; 3]> = None;
    for e in expand_moves(program, o) {
        match e {
            Event::Section(_) => secs += o.spin_up_secs,
            Event::Arc { x, y, z, len, feed, .. } => {
                secs += len / feed.max(1.0) * 60.0;
                pos = Some([x, y, z]);
            }
            Event::Move { x, y, z, rapid, feed } => {
                if let Some(p) = pos {
                    let nx = x.unwrap_or(p[0]);
                    let ny = y.unwrap_or(p[1]);
                    let d = ((nx - p[0]).powi(2) + (ny - p[1]).powi(2) + (z - p[2]).powi(2)).sqrt();
                    let rate = if rapid { o.rapid_rate } else { feed.max(1.0) };
                    if d.is_finite() {
                        secs += d / rate * 60.0;
                    }
                    pos = Some([nx, ny, z]);
                } else {
                    pos = Some([x.unwrap_or(0.0), y.unwrap_or(0.0), z]);
                }
            }
        }
    }
    secs
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn square_program() -> Program {
        let sq = |z: f64, link| Path3 { pts: vec![[0., 0., z], [10., 0., z], [10., 10., z], [0., 10., z], [0., 0., z]], link };
        Program { sections: vec![Section { name: "cut".into(), tool_number: 1, feed: 600.0, plunge: 200.0, rpm: 10000.0, paths: vec![sq(-1.0, false), sq(-2.0, true)] }] }
    }

    fn circle_program() -> Program {
        let ring: Vec<[f64; 2]> = (0..64).map(|k| {
            let a = 2.0 * std::f64::consts::PI * k as f64 / 64.0;
            [10.0 * a.cos(), 10.0 * a.sin()]
        }).collect();
        let paths = crate::cam::ring_passes_ex(&ring, &[-1.0], 1.0, None, 0.0, 0.0);
        Program { sections: vec![Section { name: "c".into(), tool_number: 1, feed: 600.0, plunge: 200.0, rpm: 10000.0, paths }] }
    }

    #[test]
    fn arcs_shrink_the_program_and_keep_every_arc_geometrically_valid() {
        let p = circle_program();
        let mut o = Output::new(&POSTS[0]);
        let plain = write(&p, &o);
        assert!(!plain.lines().any(|l| l.starts_with("G2 ") || l.starts_with("G3 ")), "arcs are opt-in (note G21 is units, not an arc)");
        o.arcs = true;
        let arcs = write(&p, &o);
        let arc_lines: Vec<&str> = arcs.lines().filter(|l| l.starts_with("G3 ") || l.starts_with("G2 ")).collect();
        assert!(!arc_lines.is_empty());
        assert!(arc_lines.iter().all(|l| l.starts_with("G3 ")), "a CCW ring is cut with G3: {arc_lines:?}");
        assert!(arc_lines.iter().all(|l| l.contains(" I") && l.contains(" J") && l.contains(" X") && l.contains(" Y")));
        assert!(arcs.lines().count() * 3 < plain.lines().count(), "{} vs {}", arcs.lines().count(), plain.lines().count());

        // every arc must have equal start and end radius, or the controller raises an alarm
        let mut pos = [f64::NAN; 3];
        let mut arcs_seen = 0;
        for e in expand_moves(&p, &o) {
            match e {
                Event::Move { x, y, z, .. } => pos = [x.unwrap_or(pos[0]), y.unwrap_or(pos[1]), z],
                Event::Arc { x, y, z, i, j, .. } => {
                    let c = [pos[0] + i, pos[1] + j];
                    let (r0, r1) = ((pos[0] - c[0]).hypot(pos[1] - c[1]), (x - c[0]).hypot(y - c[1]));
                    assert!((r0 - r1).abs() < 1e-6 && (r0 - 10.0).abs() < 0.01, "r0 {r0} r1 {r1}");
                    pos = [x, y, z];
                    arcs_seen += 1;
                }
                Event::Section(_) => {}
            }
        }
        assert!(arcs_seen >= 1);
    }

    #[test]
    fn arc_preview_samples_lie_on_the_circle_and_time_is_close_to_the_line_version() {
        let p = circle_program();
        let mut o = Output::new(&POSTS[0]);
        let t_lines = estimate_seconds(&p, &o);
        let pv_lines = preview(&p, &o);
        o.arcs = true;
        let t_arcs = estimate_seconds(&p, &o);
        let pv = preview(&p, &o);
        for m in pv.chunks_exact(4).filter(|m| m[3] == 0.0 && m[2] == -1.0) {
            assert!(((m[0] as f64).hypot(m[1] as f64) - 10.0).abs() < 0.02, "sample off the circle: {m:?}");
        }
        assert!(pv.len() >= pv_lines.len() / 2, "sampled arcs keep the preview dense enough to look round");
        assert!((t_arcs - t_lines).abs() / t_lines < 0.05, "{t_arcs} vs {t_lines}");
    }

    #[test]
    fn first_move_is_a_retract_and_linked_pass_stays_down() {
        let o = Output::new(&POSTS[0]);
        let ev = expand_moves(&square_program(), &o);
        assert!(matches!(ev[1], Event::Move { x: None, y: None, rapid: true, .. }));
        // exactly one plunge from clear height for pass 1, none for the linked pass 2
        let plunges = ev.iter().filter(|e| matches!(e, Event::Move { x: Some(_), rapid: false, feed, .. } if (*feed - 200.0).abs() < 1e-9)).count();
        assert_eq!(plunges, 2); // initial plunge + vertical link-down to -2 clamped at plunge rate
        assert!(matches!(ev.last().unwrap(), Event::Move { z, rapid: true, .. } if (*z - 5.0).abs() < 1e-9));
    }

    #[test]
    fn preview_is_four_floats_per_move_and_ends_at_safe_z() {
        let o = Output::new(&POSTS[0]);
        let p = preview(&square_program(), &o);
        assert_eq!(p.len() % 4, 0);
        assert_eq!(p.len() / 4, expand_moves(&square_program(), &o).iter().filter(|e| matches!(e, Event::Move { .. })).count());
        assert_eq!(p[p.len() - 2], 5.0); // last z = safe z
        assert_eq!(p[p.len() - 1], 1.0); // retract is a rapid
    }

    #[test]
    fn time_estimate_is_dominated_by_feed_moves() {
        let o = Output::new(&POSTS[0]);
        let t = estimate_seconds(&square_program(), &o);
        // 80 mm of cutting at 600 mm/min = 8 s, plus 3 s spin-up, plus plunges/rapids
        assert!(t > 11.0 && t < 25.0, "{t}");
    }
}
