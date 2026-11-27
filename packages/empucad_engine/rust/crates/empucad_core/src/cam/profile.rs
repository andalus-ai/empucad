use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    /// Tool centre outside every outer edge (frees a part).
    Outside,
    /// Tool centre inside every outer edge and inside every hole (makes a hole / cuts inside the line).
    Inside,
    /// Tool centre on the line.
    On,
}

/// Cut out along the outline.
pub struct Profile {
    pub side: Side,
}

impl ToolpathStrategy for Profile {
    fn generate(&self, geo: &Geometry, tool: &Tool, cut: &CutParams) -> Vec<Path3> {
        let r = tool.radius();
        let levels = depth_levels(cut.depth, cut.step_down);
        let climb = cut.direction == Direction::Climb;
        // (ring, is_outer)
        let rings: Vec<(Vec<Pt>, bool)> = match self.side {
            Side::Outside => geo.region.offset(r).rings().into_iter().filter(|(_, hole)| !hole).map(|(p, _)| (p, true)).collect(),
            Side::On => geo.region.rings().into_iter().map(|(p, hole)| (p, !hole)).collect(),
            Side::Inside => {
                let mut v: Vec<(Vec<Pt>, bool)> = geo.region.offset(-r).rings().into_iter().filter(|(_, h)| !h).map(|(p, _)| (p, false)).collect();
                // holes shrink when the region grows: tool stays inside the hole
                v.extend(geo.region.offset(r).rings().into_iter().filter(|(_, h)| *h).map(|(p, _)| (p, false)));
                v
            }
        };
        rings
            .into_iter()
            .flat_map(|(ring, outside)| {
                // climb: CCW outside, CW inside
                let ring = if cut.dogbones && self.side == Side::Inside { add_dogbones(&ring, r) } else { ring };
                let ring = orient_ring(ring, outside == climb);
                ring_passes_ex(&ring, &levels, cut.depth, cut.tabs.as_ref(), cut.ramp_length, 0.0)
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom2d::signed_area;

    fn geo() -> Geometry {
        Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [20., 0.], [20., 20.], [0., 20.]])]), lines: vec![] }
    }
    fn xy_bounds(p: &Path3) -> (f64, f64) {
        let xs: Vec<f64> = p.pts.iter().map(|q| q[0]).collect();
        (xs.iter().cloned().fold(f64::MAX, f64::min), xs.iter().cloned().fold(f64::MIN, f64::max))
    }

    #[test]
    fn outside_profile_is_offset_by_tool_radius_with_one_path_per_level() {
        let paths = Profile { side: Side::Outside }.generate(&geo(), &Tool::end_mill(3.0), &CutParams { depth: 3.0, step_down: 1.0, ..Default::default() });
        assert_eq!(paths.len(), 3);
        let (lo, hi) = xy_bounds(&paths[0]);
        assert!((lo + 1.5).abs() < 1e-3 && (hi - 21.5).abs() < 1e-3, "{lo} {hi}");
        assert_eq!(paths.iter().map(|p| p.pts[0][2]).collect::<Vec<_>>(), vec![-1.0, -2.0, -3.0]);
        assert!(!paths[0].link && paths[1].link && paths[2].link);
    }

    #[test]
    fn inside_profile_shrinks_and_climb_direction_flips() {
        let tool = Tool::end_mill(4.0);
        let climb = Profile { side: Side::Inside }.generate(&geo(), &tool, &CutParams { depth: 1.0, ..Default::default() });
        let (lo, hi) = xy_bounds(&climb[0]);
        assert!((lo - 2.0).abs() < 1e-3 && (hi - 18.0).abs() < 1e-3);
        let xy = |p: &Path3| p.pts.iter().map(|q| [q[0], q[1]]).collect::<Vec<_>>();
        assert!(signed_area(&xy(&climb[0])) < 0.0, "inside climb is CW");
        let conv = Profile { side: Side::Inside }.generate(&geo(), &tool, &CutParams { depth: 1.0, direction: Direction::Conventional, ..Default::default() });
        assert!(signed_area(&xy(&conv[0])) > 0.0);
        let out = Profile { side: Side::Outside }.generate(&geo(), &tool, &CutParams { depth: 1.0, ..Default::default() });
        assert!(signed_area(&xy(&out[0])) > 0.0, "outside climb is CCW");
    }
}
