//! Toolpath generation. Every operation is a [`ToolpathStrategy`]; add a new one by adding a type,
//! never by editing the existing ones (open/closed principle).
//!
//! Job coordinates: millimetres, Z = 0 at the top of the stock, cuts are negative.
mod drill;
mod engrave;
mod pocket;
mod profile;
mod vcarve;

pub use drill::Drill;
pub use engrave::Engrave;
pub use pocket::Pocket;
pub use profile::{Profile, Side};
pub use vcarve::VCarve;

use crate::geom2d::{signed_area, Region};
use crate::types::{Path3, Polyline, Pt};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ToolKind {
    EndMill,
    BallNose,
    VBit,
    Drill,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Tool {
    pub kind: ToolKind,
    pub diameter: f64,
    /// Included angle in degrees; only meaningful for V-bits.
    pub angle_deg: f64,
    pub name: String,
}

impl Tool {
    pub fn end_mill(diameter: f64) -> Self {
        Self { kind: ToolKind::EndMill, diameter, angle_deg: 0.0, name: String::new() }
    }
    pub fn v_bit(diameter: f64, angle_deg: f64) -> Self {
        Self { kind: ToolKind::VBit, diameter, angle_deg, name: String::new() }
    }
    pub fn radius(&self) -> f64 {
        self.diameter / 2.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Climb,
    Conventional,
}

/// Holding tabs: the cutter rises to `height` above the bottom for `width` mm of path, `count`
/// times around each profile. Width is measured along the tool-centre path.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tabs {
    pub count: u32,
    pub width: f64,
    pub height: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CutParams {
    /// Total depth below the stock top, positive.
    pub depth: f64,
    /// Maximum depth per pass, positive.
    pub step_down: f64,
    /// Pocket stepover as a fraction of tool diameter, (0, 1].
    pub step_over: f64,
    pub direction: Direction,
    /// Profiles only.
    pub tabs: Option<Tabs>,
    /// Descend along the path over this length instead of plunging straight down. 0 = plunge.
    pub ramp_length: f64,
    /// Cut relief into sharp inside corners so a square part fits (inside profiles and pocket walls).
    pub dogbones: bool,
}

impl Default for CutParams {
    fn default() -> Self {
        Self { depth: 3.0, step_down: 1.0, step_over: 0.45, direction: Direction::Climb, tabs: None, ramp_length: 0.0, dogbones: false }
    }
}

/// Everything a strategy may read. Closed shapes live in `region`, raw lines in `lines`.
#[derive(Clone, Debug, Default)]
pub struct Geometry {
    pub region: Region,
    pub lines: Vec<Polyline>,
}

pub trait ToolpathStrategy {
    fn generate(&self, geo: &Geometry, tool: &Tool, cut: &CutParams) -> Vec<Path3>;
}

/// Negative Z levels, shallow to deep; the last level is exactly `-depth`.
pub fn depth_levels(depth: f64, step: f64) -> Vec<f64> {
    if depth <= 0.0 {
        return vec![];
    }
    let step = if step <= 0.0 { depth } else { step };
    let n = (depth / step - 1e-9).ceil().max(1.0) as usize;
    (1..=n).map(|i| -(depth * i as f64 / n as f64)).collect()
}

/// Rule of thumb for a clockwise spindle: climb = CCW around an outside edge, CW inside a pocket.
pub(crate) fn orient_ring(mut ring: Vec<Pt>, ccw: bool) -> Vec<Pt> {
    if (signed_area(&ring) > 0.0) != ccw {
        ring.reverse();
    }
    ring
}

/// Dogbone relief for a tool-centre ring the cutter travels INSIDE of (inside profile, pocket wall).
///
/// A round cutter cannot reach a sharp inside corner: the finished corner is rounded to the tool
/// radius `r`. At each sharp convex vertex of the ring the path therefore runs out along the corner's
/// bisector and back, far enough that the cutter's edge reaches the true corner. For interior angle
/// `theta` that extra travel is `r / sin(theta / 2) - r` (0.414 r for a square corner). Gentle turns
/// (the flattened arcs of rounded corners) and very acute corners are left alone.
pub(crate) fn add_dogbones(ring: &[Pt], r: f64) -> Vec<Pt> {
    let n = ring.len();
    if n < 3 || r <= 0.0 {
        return ring.to_vec();
    }
    let ccw = signed_area(ring) > 0.0;
    let mut out = Vec::with_capacity(n + 8);
    for i in 0..n {
        let (a, p, b) = (ring[(i + n - 1) % n], ring[i], ring[(i + 1) % n]);
        out.push(p);
        let (d1, d2) = ([p[0] - a[0], p[1] - a[1]], [b[0] - p[0], b[1] - p[1]]);
        let (l1, l2) = (d1[0].hypot(d1[1]), d2[0].hypot(d2[1]));
        if l1 < 1e-9 || l2 < 1e-9 {
            continue;
        }
        let (u1, u2) = ([d1[0] / l1, d1[1] / l1], [d2[0] / l2, d2[1] / l2]);
        let turn = (u1[0] * u2[1] - u1[1] * u2[0]).atan2(u1[0] * u2[0] + u1[1] * u2[1]);
        let convex = if ccw { turn > 0.0 } else { turn < 0.0 };
        let theta = std::f64::consts::PI - turn.abs(); // interior angle at this vertex
        if !convex || turn.abs() < 35f64.to_radians() || theta < 20f64.to_radians() {
            continue;
        }
        // outward normals of the two edges (away from the ring interior), then the bisector
        let out_n = |u: [f64; 2]| if ccw { [u[1], -u[0]] } else { [-u[1], u[0]] };
        let (n1, n2) = (out_n(u1), out_n(u2));
        let bis = [n1[0] + n2[0], n1[1] + n2[1]];
        let bl = bis[0].hypot(bis[1]);
        if bl < 1e-9 {
            continue;
        }
        let ext = r / (theta / 2.0).sin() - r;
        let q = [p[0] + bis[0] / bl * ext, p[1] + bis[1] / bl * ext];
        out.push(q);
        out.push(p);
    }
    out
}

/// One closed path per depth level around `ring`, with optional tabs and ramp entry.
///
/// `z_before` is the depth the cutter is at before the first level (0 = stock top, or the previous
/// pocket level). With a ramp, every level begins where the previous one ended, so consecutive
/// levels link without any chord across the ring.
pub(crate) fn ring_passes_ex(ring: &[Pt], levels: &[f64], depth: f64, tabs: Option<&Tabs>, ramp: f64, z_before: f64) -> Vec<Path3> {
    let n = ring.len();
    let mut cum = Vec::with_capacity(n + 1);
    cum.push(0.0);
    for i in 0..n {
        let (a, b) = (ring[i], ring[(i + 1) % n]);
        cum.push(cum[i] + (b[0] - a[0]).hypot(b[1] - a[1]));
    }
    let total = cum[n];
    if total < 1e-9 || levels.is_empty() {
        return vec![];
    }
    let point_at = |s: f64| -> Pt {
        let s = s.rem_euclid(total);
        let i = cum.partition_point(|&c| c <= s).saturating_sub(1).min(n - 1);
        let t = if cum[i + 1] - cum[i] < 1e-12 { 0.0 } else { (s - cum[i]) / (cum[i + 1] - cum[i]) };
        let (a, b) = (ring[i], ring[(i + 1) % n]);
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
    };
    // tab spans (absolute arclength) and the height they lift the cutter to
    let mut spans: Vec<(f64, f64)> = vec![];
    let mut tab_z = f64::NEG_INFINITY;
    if let Some(t) = tabs {
        if t.count > 0 && t.width > 0.0 && t.height > 0.0 && t.height < depth {
            tab_z = -depth + t.height;
            let w = t.width.min(total / t.count as f64 * 0.9);
            for k in 0..t.count {
                let c = total * (k as f64 + 0.5) / t.count as f64;
                spans.push((c - w / 2.0, c + w / 2.0));
            }
        }
    }
    // open intervals: a tab edge is a vertical step, not part of the tab
    let in_tab = |s: f64| {
        let s = s.rem_euclid(total);
        spans.iter().any(|&(a, b)| s > a && s < b)
    };
    let ramp = ramp.clamp(0.0, total / 2.0);
    let mut out = Vec::new();
    let mut s0 = 0.0;
    let mut prev = z_before;
    for (li, &z) in levels.iter().enumerate() {
        let base = |s: f64, z: f64| if z < tab_z && in_tab(s) { tab_z } else { z };
        // breakpoints as offsets u from the start s0: vertices, tab edges, ramp end
        let mut us: Vec<f64> = vec![0.0];
        let mut add = |abs: f64| us.push((abs - s0).rem_euclid(total));
        for &c in &cum[..n] {
            add(c);
        }
        for &(a, b) in &spans {
            add(a);
            add(b);
        }
        if ramp > 0.0 {
            us.push(ramp);
        }
        us.sort_by(|a, b| a.partial_cmp(b).unwrap());
        us.dedup_by(|a, b| (*a - *b).abs() < 1e-9);
        const EPS: f64 = 1e-7;
        let zf = |u: f64, use_ramp: bool| -> f64 {
            let b = base(s0 + u, z);
            if use_ramp && ramp > 0.0 && u <= ramp + 1e-9 {
                (prev + (z - prev) * (u.max(0.0) / ramp)).max(b)
            } else {
                b
            }
        };
        // Emit the point at offset `u`; where the height jumps (tab edge) emit both sides so the
        // step is vertical rather than a slope along the path.
        // `end`: 0 = first point of the path, 1 = interior, 2 = last point of the path.
        let push = |pts: &mut Vec<[f64; 3]>, u: f64, use_ramp: bool, end: u8| {
            let p = point_at(s0 + u);
            let (zl, zr) = (zf(u - EPS, use_ramp), zf(u + EPS, use_ramp));
            let step = (zl - zr).abs() > 1e-4; // a slope over 2*EPS is ~1e-8, far below this
            let exact = zf(u, use_ramp);
            match (end, step) {
                (0, true) => pts.push([p[0], p[1], zr]),
                (2, true) => pts.push([p[0], p[1], zl]),
                (1, true) => {
                    pts.push([p[0], p[1], zl]);
                    pts.push([p[0], p[1], zr]);
                }
                _ => pts.push([p[0], p[1], exact]),
            }
        };
        let mut pts: Vec<[f64; 3]> = Vec::new();
        for (k, &u) in us.iter().enumerate() {
            push(&mut pts, u, true, if k == 0 { 0 } else { 1 });
        }
        push(&mut pts, total, true, if ramp > 0.0 { 1 } else { 2 }); // back to the start point
        if ramp > 0.0 {
            // re-cut the ramped stretch at full depth
            let recut: Vec<f64> = us.iter().copied().filter(|&u| u > 1e-9 && u <= ramp + 1e-9).collect();
            for (k, &u) in recut.iter().enumerate() {
                let last = k + 1 == recut.len();
                push(&mut pts, total + u, false, if last { 2 } else { 1 });
            }
            s0 = (s0 + ramp).rem_euclid(total);
        }
        out.push(Path3 { pts, link: li > 0 });
        prev = z;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn square20() -> Vec<Pt> {
        vec![[0., 0.], [20., 0.], [20., 20.], [0., 20.]]
    }

    fn flat_len(p: &Path3, pred: impl Fn(f64, f64) -> bool) -> f64 {
        p.pts.windows(2).filter(|w| pred(w[0][2], w[1][2])).map(|w| (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1])).sum()
    }

    #[test]
    fn tabs_lift_only_the_deepest_pass_by_the_requested_width() {
        let levels = depth_levels(3.0, 1.0);
        let tabs = Tabs { count: 4, width: 6.0, height: 1.0 };
        let paths = ring_passes_ex(&square20(), &levels, 3.0, Some(&tabs), 0.0, 0.0);
        assert_eq!(paths.len(), 3);
        // passes above the tab top are untouched: a single constant z
        for (p, z) in paths.iter().zip([-1.0, -2.0]) {
            assert!(p.pts.iter().all(|q| (q[2] - z).abs() < 1e-9));
        }
        let last = &paths[2];
        let on_tab = flat_len(last, |a, b| (a + 2.0).abs() < 1e-9 && (b + 2.0).abs() < 1e-9);
        let on_floor = flat_len(last, |a, b| (a + 3.0).abs() < 1e-9 && (b + 3.0).abs() < 1e-9);
        assert!((on_tab - 24.0).abs() < 1e-6, "tab length {on_tab}");
        assert!((on_floor - 56.0).abs() < 1e-6, "floor length {on_floor}");
        assert!(last.pts.iter().all(|q| q[2] >= -3.0 - 1e-9 && q[2] <= -2.0 + 1e-9));
    }

    #[test]
    fn tab_taller_than_the_cut_is_ignored() {
        let tabs = Tabs { count: 4, width: 6.0, height: 5.0 };
        let p = ring_passes_ex(&square20(), &[-1.0, -2.0], 2.0, Some(&tabs), 0.0, 0.0);
        assert!(p[1].pts.iter().all(|q| (q[2] + 2.0).abs() < 1e-9));
    }

    #[test]
    fn ramp_descends_monotonically_over_its_length_then_recuts_it() {
        let paths = ring_passes_ex(&square20(), &[-1.0], 1.0, None, 10.0, 0.0);
        let p = &paths[0];
        assert_eq!(p.pts[0][2], 0.0, "starts at the stock top");
        let mut dist = 0.0;
        let mut last_z = 0.0;
        for w in p.pts.windows(2) {
            if dist >= 10.0 - 1e-9 {
                break;
            }
            dist += (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1]);
            assert!(w[1][2] <= last_z + 1e-9, "z must not rise during the ramp");
            last_z = w[1][2];
        }
        assert!((last_z + 1.0).abs() < 1e-9, "ramp ends at full depth, got {last_z}");
        // loop (80) + ramp re-cut (10)
        let total: f64 = p.pts.windows(2).map(|w| (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1])).sum();
        assert!((total - 90.0).abs() < 1e-6, "{total}");
        // after the ramp every point is at full depth
        assert!(p.pts.iter().skip(4).all(|q| (q[2] + 1.0).abs() < 1e-9));
    }

    #[test]
    fn ramped_levels_start_where_the_previous_one_ended() {
        let paths = ring_passes_ex(&square20(), &[-1.0, -2.0], 2.0, None, 10.0, 0.0);
        let (end, start) = (paths[0].pts.last().unwrap(), paths[1].pts.first().unwrap());
        assert!((end[0] - start[0]).abs() < 1e-9 && (end[1] - start[1]).abs() < 1e-9);
        assert!((end[2] - start[2]).abs() < 1e-9, "second ramp starts at the previous depth");
        assert!(paths[1].link);
    }

    #[test]
    fn depth_levels_end_exactly_at_depth() {
        assert_eq!(depth_levels(3.0, 1.0), vec![-1.0, -2.0, -3.0]);
        let l = depth_levels(2.5, 1.0);
        assert_eq!(l.len(), 3);
        assert!((l[2] + 2.5).abs() < 1e-12);
        assert_eq!(depth_levels(1.0, 5.0), vec![-1.0]);
        assert!(depth_levels(0.0, 1.0).is_empty());
    }
}

#[cfg(test)]
mod dogbone_tests {
    use super::*;

    fn square(lo: f64, hi: f64) -> Vec<Pt> {
        vec![[lo, lo], [hi, lo], [hi, hi], [lo, hi]]
    }

    #[test]
    fn square_corners_get_a_relief_that_reaches_exactly_one_tool_radius_from_the_true_corner() {
        // tool radius 3 cutting inside a 0..20 square: the tool-centre ring is the 3..17 square
        let ring = square(3.0, 17.0);
        let out = add_dogbones(&ring, 3.0);
        assert_eq!(out.len(), 12, "4 corners, each gets an out point and a return point");
        let truth = [[0., 0.], [20., 0.], [20., 20.], [0., 20.]];
        for t in truth {
            let nearest = out.iter().map(|q| (q[0] - t[0]).hypot(q[1] - t[1])).fold(f64::MAX, f64::min);
            assert!((nearest - 3.0).abs() < 1e-9, "relief ends r from the true corner: {nearest}");
        }
        // and every relief point stays inside the original shape
        assert!(out.iter().all(|q| q[0] >= 0.0 && q[0] <= 20.0 && q[1] >= 0.0 && q[1] <= 20.0));
        // the relief lies on the corner's diagonal: 3 / sqrt(2) = 2.1213 from each wall
        let q = out[1];
        assert!((q[0] - q[1]).abs() < 1e-9 && (q[0] - 2.1213203435596424).abs() < 1e-9, "{q:?}");
    }

    #[test]
    fn orientation_does_not_matter() {
        let mut cw = square(3.0, 17.0);
        cw.reverse();
        let out = add_dogbones(&cw, 3.0);
        assert_eq!(out.len(), 12);
        assert!(out.iter().all(|q| q[0] >= 0.0 && q[0] <= 20.0 && q[1] >= 0.0 && q[1] <= 20.0), "relief points go outward, not across the shape");
    }

    #[test]
    fn extra_travel_follows_r_over_sin_half_theta_minus_r() {
        // 60-degree interior angle at the apex of an equilateral triangle
        let h = 3.0f64.sqrt() / 2.0 * 30.0;
        let tri = vec![[0.0, 0.0], [30.0, 0.0], [15.0, h]];
        let out = add_dogbones(&tri, 2.0);
        assert_eq!(out.len(), 9);
        let (p, q) = (out[0], out[1]);
        let ext = (q[0] - p[0]).hypot(q[1] - p[1]);
        assert!((ext - (2.0 / 30f64.to_radians().sin() - 2.0)).abs() < 1e-9, "{ext}");
    }

    #[test]
    fn round_corners_and_reflex_corners_are_left_alone() {
        // a circle (64 small turns)
        let circle: Vec<Pt> = (0..64).map(|k| {
            let a = 2.0 * std::f64::consts::PI * k as f64 / 64.0;
            [10.0 * a.cos(), 10.0 * a.sin()]
        }).collect();
        assert_eq!(add_dogbones(&circle, 3.0).len(), 64);
        // an L-shape: five convex corners, one reflex corner; the reflex one gets nothing
        let l = vec![[0., 0.], [20., 0.], [20., 10.], [10., 10.], [10., 20.], [0., 20.]];
        let out = add_dogbones(&l, 1.0);
        assert_eq!(out.len(), 6 + 5 * 2);
    }

    #[test]
    fn very_acute_corners_and_degenerate_input_are_safe() {
        let spike = vec![[0., 0.], [100., 4.], [100., -4.]]; // ~4.6 degree tip
        assert_eq!(add_dogbones(&spike, 1.0).len(), 3 + 2 * 2, "only the two obtuse-enough corners are relieved");
        assert_eq!(add_dogbones(&[], 1.0).len(), 0);
        assert_eq!(add_dogbones(&square(0., 5.), 0.0), square(0., 5.), "zero radius: nothing to do");
    }

    fn geo(w: f64) -> Geometry {
        Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [w, 0.], [w, w], [0., w]])]), lines: vec![] }
    }

    #[test]
    fn inside_profile_with_dogbones_reaches_every_corner_and_only_inside_profiles_get_them() {
        let tool = Tool::end_mill(6.0);
        let on = CutParams { depth: 1.0, dogbones: true, ..Default::default() };
        let paths = Profile { side: Side::Inside }.generate(&geo(20.0), &tool, &on);
        let pts: Vec<[f64; 2]> = paths[0].pts.iter().map(|p| [p[0], p[1]]).collect();
        for t in [[0., 0.], [20., 0.], [20., 20.], [0., 20.]] {
            let nearest = pts.iter().map(|q| (q[0] - t[0]).hypot(q[1] - t[1])).fold(f64::MAX, f64::min);
            assert!((nearest - 3.0).abs() < 1e-3, "cutter edge reaches corner {t:?}: {nearest}");
        }
        let off = CutParams { depth: 1.0, ..Default::default() };
        assert!(Profile { side: Side::Inside }.generate(&geo(20.0), &tool, &off)[0].pts.len() < paths[0].pts.len());
        // outside profiles are unaffected by the flag (dogbones make no sense there)
        let o1 = Profile { side: Side::Outside }.generate(&geo(20.0), &tool, &on);
        let o2 = Profile { side: Side::Outside }.generate(&geo(20.0), &tool, &off);
        assert_eq!(o1[0].pts, o2[0].pts);
    }

    #[test]
    fn pocket_dogbones_touch_only_the_wall_pass() {
        let tool = Tool::end_mill(4.0);
        let base = CutParams { depth: 1.0, step_over: 0.5, ..Default::default() };
        let plain = Pocket.generate(&geo(30.0), &tool, &base);
        let bone = Pocket.generate(&geo(30.0), &tool, &CutParams { dogbones: true, ..base.clone() });
        assert_eq!(plain.len(), bone.len(), "same number of rings");
        let changed: Vec<usize> = (0..plain.len()).filter(|&i| plain[i].pts != bone[i].pts).collect();
        assert_eq!(changed, vec![0], "only the outermost ring changes");
        assert_eq!(bone[0].pts.len(), plain[0].pts.len() + 8);
    }
}
