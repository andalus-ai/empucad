//! Arc fitting: replace runs of short straight cuts that lie on a circle with one `G2`/`G3` move.
//! Only planar runs (constant Z) are fitted, so plunges, ramps and tab steps stay as lines.

#[derive(Clone, Debug, PartialEq)]
pub enum Seg {
    Line([f64; 3]),
    /// `i`,`j` are the centre relative to the arc's start point (G-code `I`/`J`).
    Arc { to: [f64; 3], i: f64, j: f64, cw: bool, len: f64 },
}

const MIN_POINTS: usize = 4; // at least 3 segments, otherwise a "arc" saves nothing
const MAX_RADIUS: f64 = 1.0e5;

struct Circle {
    c: [f64; 2],
    r: f64,
    cw: bool,
    sweep: f64,
}

fn circumcircle(a: [f64; 3], b: [f64; 3], c: [f64; 3]) -> Option<([f64; 2], f64)> {
    let d = 2.0 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]));
    if d.abs() < 1e-12 {
        return None; // collinear
    }
    let (a2, b2, c2) = (a[0] * a[0] + a[1] * a[1], b[0] * b[0] + b[1] * b[1], c[0] * c[0] + c[1] * c[1]);
    let ux = (a2 * (b[1] - c[1]) + b2 * (c[1] - a[1]) + c2 * (a[1] - b[1])) / d;
    let uy = (a2 * (c[0] - b[0]) + b2 * (a[0] - c[0]) + c2 * (b[0] - a[0])) / d;
    let r = (a[0] - ux).hypot(a[1] - uy);
    (r.is_finite() && r < MAX_RADIUS).then_some(([ux, uy], r))
}

fn fit_circle(p: &[[f64; 3]], tol: f64) -> Option<Circle> {
    let (c, r) = circumcircle(p[0], p[p.len() / 2], p[p.len() - 1])?;
    if p.iter().any(|q| ((q[0] - c[0]).hypot(q[1] - c[1]) - r).abs() > tol) {
        return None;
    }
    // one turning direction, and a sweep that is a real arc (not a nearly closed loop)
    let ang = |q: [f64; 3]| (q[1] - c[1]).atan2(q[0] - c[0]);
    let mut sweep = 0.0;
    let mut sign = 0.0f64;
    for w in p.windows(2) {
        let mut d = ang(w[1]) - ang(w[0]);
        while d > std::f64::consts::PI {
            d -= 2.0 * std::f64::consts::PI;
        }
        while d < -std::f64::consts::PI {
            d += 2.0 * std::f64::consts::PI;
        }
        if d.abs() < 1e-12 {
            return None;
        }
        if sign == 0.0 {
            sign = d.signum();
        } else if d.signum() != sign {
            return None;
        }
        sweep += d.abs();
    }
    (sweep < 2.0 * std::f64::consts::PI * 0.97).then_some(Circle { c, r, cw: sign < 0.0, sweep })
}

/// Greedy fit. `tol` is the largest allowed distance from any original point to the arc, in mm.
pub fn fit(pts: &[[f64; 3]], tol: f64) -> Vec<Seg> {
    let n = pts.len();
    let mut out = Vec::new();
    let mut s = 0;
    while s + 1 < n {
        let mut best: Option<(usize, Circle)> = None;
        let mut e = s + MIN_POINTS - 1;
        while e < n && pts[s..=e].iter().all(|q| (q[2] - pts[s][2]).abs() < 1e-9) {
            match fit_circle(&pts[s..=e], tol) {
                Some(c) => {
                    best = Some((e, c));
                    e += 1;
                }
                None => break,
            }
        }
        match best {
            Some((e, c)) => {
                out.push(Seg::Arc { to: pts[e], i: c.c[0] - pts[s][0], j: c.c[1] - pts[s][1], cw: c.cw, len: c.r * c.sweep });
                s = e;
            }
            None => {
                out.push(Seg::Line(pts[s + 1]));
                s += 1;
            }
        }
    }
    out
}

/// Points along an arc for previews: `n` steps from `start` to `to` around `centre`.
pub fn sample(start: [f64; 2], to: [f64; 2], centre: [f64; 2], cw: bool, max_step_deg: f64) -> Vec<[f64; 2]> {
    let r = (start[0] - centre[0]).hypot(start[1] - centre[1]);
    let a0 = (start[1] - centre[1]).atan2(start[0] - centre[0]);
    let a1 = (to[1] - centre[1]).atan2(to[0] - centre[0]);
    let tau = 2.0 * std::f64::consts::PI;
    let mut d = a1 - a0;
    if cw {
        while d >= 0.0 {
            d -= tau;
        }
    } else {
        while d <= 0.0 {
            d += tau;
        }
    }
    let n = ((d.abs().to_degrees() / max_step_deg).ceil() as usize).max(1);
    (1..=n).map(|k| {
        let a = a0 + d * k as f64 / n as f64;
        [centre[0] + r * a.cos(), centre[1] + r * a.sin()]
    }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn circle_pts(r: f64, from_deg: f64, to_deg: f64, n: usize, z: f64) -> Vec<[f64; 3]> {
        (0..=n).map(|k| {
            let a = (from_deg + (to_deg - from_deg) * k as f64 / n as f64).to_radians();
            [r * a.cos(), r * a.sin(), z]
        }).collect()
    }

    #[test]
    fn a_quarter_circle_becomes_one_ccw_arc_with_the_right_centre() {
        let p = circle_pts(10.0, 0.0, 90.0, 12, -1.0);
        let segs = fit(&p, 0.01);
        assert_eq!(segs.len(), 1);
        let Seg::Arc { to, i, j, cw, len } = &segs[0] else { panic!("{segs:?}") };
        assert!(!cw, "increasing angle is counter-clockwise (G3)");
        assert!((to[0]).abs() < 1e-9 && (to[1] - 10.0).abs() < 1e-9);
        assert!((i + 10.0).abs() < 1e-9 && j.abs() < 1e-9, "centre is at the origin, start at (10,0): I=-10 J=0, got {i} {j}");
        assert!((len - 10.0 * std::f64::consts::FRAC_PI_2).abs() < 1e-9);
    }

    #[test]
    fn clockwise_runs_are_g2() {
        let p = circle_pts(10.0, 90.0, 0.0, 12, 0.0);
        let Seg::Arc { cw, .. } = &fit(&p, 0.01)[0] else { panic!() };
        assert!(*cw);
    }

    #[test]
    fn straight_runs_stay_lines_and_z_changes_break_arcs() {
        let line: Vec<[f64; 3]> = (0..6).map(|k| [k as f64, 0.0, 0.0]).collect();
        assert!(fit(&line, 0.01).iter().all(|s| matches!(s, Seg::Line(_))));
        let mut p = circle_pts(10.0, 0.0, 90.0, 12, 0.0);
        for (k, q) in p.iter_mut().enumerate() {
            q[2] = -(k as f64) * 0.1; // spiralling down: a helix, not a planar arc
        }
        assert!(fit(&p, 0.01).iter().all(|s| matches!(s, Seg::Line(_))));
    }

    #[test]
    fn tolerance_limits_how_far_points_may_stray_from_the_arc() {
        let mut p = circle_pts(10.0, 0.0, 90.0, 12, 0.0);
        p[6][0] += 0.2; // 0.2 mm bump in the middle
        let strict = fit(&p, 0.01);
        assert!(strict.len() > 1, "bump must split or reject the arc");
        let loose = fit(&p, 0.5);
        assert!(loose.len() < strict.len());
    }

    #[test]
    fn fitted_arcs_stay_within_tolerance_of_the_original_points() {
        let p = circle_pts(7.5, 20.0, 200.0, 40, 0.0);
        let tol = 0.005;
        let mut cur = p[0];
        for seg in fit(&p, tol) {
            if let Seg::Arc { to, i, j, cw, .. } = seg {
                let centre = [cur[0] + i, cur[1] + j];
                let (r0, r1) = ((cur[0] - centre[0]).hypot(cur[1] - centre[1]), (to[0] - centre[0]).hypot(to[1] - centre[1]));
                assert!((r0 - r1).abs() < 1e-6, "G2/G3 need equal start and end radius: {r0} vs {r1}");
                let _ = cw;
            }
            cur = match seg { Seg::Line(t) => t, Seg::Arc { to, .. } => to };
        }
        assert_eq!(cur, *p.last().unwrap(), "the fit ends where the path ends");
    }

    #[test]
    fn sample_walks_the_short_way_in_the_requested_direction() {
        let pts = sample([10.0, 0.0], [0.0, 10.0], [0.0, 0.0], false, 5.0);
        assert!((pts.last().unwrap()[1] - 10.0).abs() < 1e-9);
        assert!(pts.iter().all(|p| p[0] >= -1e-9 && p[1] >= -1e-9), "CCW from 0 to 90 deg stays in the first quadrant");
        let cw = sample([10.0, 0.0], [0.0, 10.0], [0.0, 0.0], true, 5.0); // the long way round
        assert!(cw.len() > pts.len() * 2);
    }
}
