//! From toolpaths to machine moves and G-code text.
//!
//! [`expand_moves`] is the single source of truth for motion: the writer, the time estimate and any
//! simulator all consume its output.
mod post;
mod writer;

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
}

impl Output {
    pub fn new(post: &'static Post) -> Self {
        Self { post, inches: false, safe_z: 5.0, clear_z: 1.0, rapid_rate: 3000.0, spin_up_secs: 3.0 }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Event {
    Section(usize),
    /// `None` coordinates are left unchanged (used for the very first retract).
    Move { x: Option<f64>, y: Option<f64>, z: f64, rapid: bool, feed: f64 },
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
            for w in path.pts.windows(2) {
                mv(&mut ev, &mut pos, w[1][0], w[1][1], w[1][2], false, cut_feed(w[0], w[1]));
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
        if let Event::Move { x, y, z, rapid, .. } = e {
            pos = [x.unwrap_or(pos[0]), y.unwrap_or(pos[1]), z];
            out.extend_from_slice(&[pos[0] as f32, pos[1] as f32, pos[2] as f32, if rapid { 1.0 } else { 0.0 }]);
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
