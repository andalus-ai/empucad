use super::*;

/// V-carve: a V-bit cuts deeper where the shape is wider, so the groove's top edge lands on the
/// outline. Done as concentric inward offsets of the outline; the ring at distance `d` from the
/// edge is cut with the bit tip at depth `d / tan(angle / 2)`.
///
/// This is the contour-parallel approximation, not a medial-axis V-carve: it leaves slightly rounded
/// inner corners and tiny ridges between rings (smaller `step_over` makes them finer). Shapes wider
/// than the bit can reach are carved to the depth limit and the middle is left uncut; clear it with a
/// pocket pass if needed.
pub struct VCarve;

/// Ring spacing never exceeds this, whatever the bit diameter or stepover: it sets the groove's
/// surface finish, and a 6 mm bit at the default 45% stepover would otherwise step 2.7 mm.
const MAX_STEP_MM: f64 = 0.5;

impl VCarve {
    /// Deepest the tip may go: the requested depth, further limited by the bit's own width
    /// (a bit of diameter D with included angle A cannot cut deeper than (D / 2) / tan(A / 2)).
    pub fn max_depth(tool: &Tool, cut: &CutParams) -> f64 {
        let t = (tool.angle_deg.to_radians() / 2.0).tan();
        if t <= 1e-9 || !t.is_finite() {
            return 0.0;
        }
        cut.depth.min(tool.radius() / t)
    }

    /// (distance from the edge, tip depth below the top) for each ring, shallow to deep.
    pub fn rings(tool: &Tool, cut: &CutParams) -> Vec<(f64, f64)> {
        let t = (tool.angle_deg.to_radians() / 2.0).tan();
        let max = Self::max_depth(tool, cut);
        if max <= 0.0 {
            return vec![];
        }
        let step = (tool.diameter * cut.step_over.clamp(0.005, 1.0)).clamp(0.02, MAX_STEP_MM);
        let mut out = Vec::new();
        let mut k = 0usize;
        loop {
            let d = k as f64 * step;
            let depth = d / t;
            if depth >= max {
                out.push((max * t, max)); // final ring exactly at the depth limit
                break;
            }
            out.push((d, depth));
            k += 1;
            if k > 100_000 {
                break;
            }
        }
        out
    }
}

impl ToolpathStrategy for VCarve {
    fn generate(&self, geo: &Geometry, tool: &Tool, cut: &CutParams) -> Vec<Path3> {
        let climb = cut.direction == Direction::Climb;
        let mut out = Vec::new();
        let mut z_before = 0.0;
        for (d, depth) in Self::rings(tool, cut) {
            let region = if d < 1e-9 { geo.region.clone() } else { geo.region.offset(-d) };
            if region.is_empty() {
                break; // the shape is narrower than this: everything deeper would be outside it
            }
            for (ring, hole) in region.rings() {
                // walk the outline like an inside profile: CW when climbing, islands the other way
                let ring = orient_ring(ring, hole == climb);
                out.extend(ring_passes_ex(&ring, &[-depth], cut.depth, None, cut.ramp_length, z_before));
            }
            z_before = -depth;
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(w: f64, h: f64) -> Geometry {
        Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [w, 0.], [w, h], [0., h]])]), lines: vec![] }
    }
    fn v(angle: f64, dia: f64) -> Tool {
        Tool { kind: ToolKind::VBit, diameter: dia, angle_deg: angle, name: String::new() }
    }
    fn bbox_inset(p: &Path3) -> f64 {
        p.pts.iter().map(|q| q[0]).fold(f64::MAX, f64::min)
    }

    #[test]
    fn ninety_degree_bit_cuts_depth_equal_to_distance_from_the_edge() {
        let cut = CutParams { depth: 3.0, step_over: 0.1, ..Default::default() }; // step = 0.5 mm for a 5 mm bit
        let paths = VCarve.generate(&rect(10.0, 4.0), &v(90.0, 5.0), &cut);
        assert!(paths.len() >= 4, "{}", paths.len());
        for p in &paths {
            let z = p.pts[0][2];
            assert!(p.pts.iter().all(|q| (q[2] - z).abs() < 1e-9), "each ring is at one depth");
            // tan(45) = 1: the ring sits `d` in from the edge, at depth -d
            assert!((bbox_inset(p) + z).abs() < 1e-2, "inset {} vs depth {z}", bbox_inset(p));
        }
        // shallow to deep
        let zs: Vec<f64> = paths.iter().map(|p| p.pts[0][2]).collect();
        assert!(zs.windows(2).all(|w| w[1] <= w[0] + 1e-9), "{zs:?}");
        assert_eq!(zs[0], 0.0, "the first ring is the outline itself, at the surface");
    }

    #[test]
    fn ring_spacing_is_capped_so_a_big_bit_with_the_default_stepover_still_carves_finely() {
        let cut = CutParams { depth: 10.0, ..Default::default() }; // default stepover 0.45
        let rings = VCarve::rings(&v(90.0, 20.0), &cut);
        let gaps: Vec<f64> = rings.windows(2).map(|w| w[1].0 - w[0].0).collect();
        assert!(gaps.iter().all(|&g| g <= 0.5 + 1e-9), "{gaps:?}");
        // and never finer than 0.02 mm, even for an absurd stepover
        let fine = VCarve::rings(&v(90.0, 20.0), &CutParams { depth: 1.0, step_over: 0.0001, ..Default::default() });
        assert!(fine.len() <= 60, "{}", fine.len());
    }

    #[test]
    fn narrow_shapes_stop_when_the_offset_collapses() {
        // 4 mm wide: rings stop before 2 mm in from the edge, so the deepest is just under 2 mm
        let cut = CutParams { depth: 10.0, ..Default::default() };
        let paths = VCarve.generate(&rect(40.0, 4.0), &v(90.0, 20.0), &cut);
        let deepest = paths.iter().map(|p| -p.pts[0][2]).fold(0.0, f64::max);
        assert!(deepest < 2.0 + 1e-6 && deepest > 1.0, "{deepest}");
    }

    #[test]
    fn depth_limit_and_bit_width_both_cap_the_depth() {
        let wide = rect(100.0, 100.0);
        let capped = VCarve.generate(&wide, &v(90.0, 20.0), &CutParams { depth: 1.5, step_over: 0.05, ..Default::default() });
        let max_z = capped.iter().map(|p| -p.pts[0][2]).fold(0.0, f64::max);
        assert!((max_z - 1.5).abs() < 1e-9, "requested depth is the limit: {max_z}");
        // a 2 mm bit at 90 deg can only cut 1 mm deep, whatever was asked
        let narrow_bit = VCarve.generate(&wide, &v(90.0, 2.0), &CutParams { depth: 5.0, step_over: 0.1, ..Default::default() });
        let max_z = narrow_bit.iter().map(|p| -p.pts[0][2]).fold(0.0, f64::max);
        assert!((max_z - 1.0).abs() < 1e-9, "{max_z}");
        assert!(VCarve::max_depth(&v(90.0, 2.0), &CutParams { depth: 5.0, ..Default::default() }) - 1.0 < 1e-9);
    }

    #[test]
    fn a_sharper_bit_goes_deeper_for_the_same_width() {
        let cut = CutParams { depth: 50.0, step_over: 0.05, ..Default::default() };
        let depth_of = |angle: f64| {
            VCarve.generate(&rect(60.0, 6.0), &v(angle, 30.0), &cut).iter().map(|p| -p.pts[0][2]).fold(0.0, f64::max)
        };
        let (d90, d60, d30) = (depth_of(90.0), depth_of(60.0), depth_of(30.0));
        assert!(d60 > d90 && d30 > d60, "{d90} {d60} {d30}");
        // 60 deg: depth = d / tan(30) = 1.732 d, with d just under 3 mm
        assert!((d60 / d90 - 3.0f64.sqrt()).abs() < 0.15, "{}", d60 / d90);
    }

    #[test]
    fn a_hole_is_carved_around_as_well() {
        let g = Geometry {
            region: Region::from_outlines(&[
                Polyline::closed(vec![[0., 0.], [40., 0.], [40., 40.], [0., 40.]]),
                Polyline::closed(vec![[15., 15.], [25., 15.], [25., 25.], [15., 25.]]),
            ]),
            lines: vec![],
        };
        let paths = VCarve.generate(&g, &v(90.0, 6.0), &CutParams { depth: 2.0, step_over: 0.1, ..Default::default() });
        let around_hole = paths.iter().filter(|p| p.pts.iter().all(|q| q[0] >= 14.0 && q[0] <= 26.0 && q[1] >= 14.0 && q[1] <= 26.0)).count();
        assert!(around_hole >= 2, "rings hug the island: {around_hole}");
    }

    #[test]
    fn degenerate_bits_produce_nothing_instead_of_looping() {
        let cut = CutParams::default();
        assert!(VCarve.generate(&rect(10., 10.), &v(0.0, 5.0), &cut).is_empty());
        assert!(VCarve.generate(&rect(10., 10.), &v(180.0, 5.0), &cut).is_empty() || VCarve::max_depth(&v(180.0, 5.0), &cut) < 1e-6);
    }
}
