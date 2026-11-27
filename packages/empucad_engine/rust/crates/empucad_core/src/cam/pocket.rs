use super::*;

/// Clear everything inside the shape with concentric offsets, outermost ring first.
pub struct Pocket;

impl Pocket {
    /// Concentric rings from the wall inward (tool-centre positions).
    pub fn rings(region: &Region, tool: &Tool, step_over: f64) -> Vec<(Vec<Pt>, bool)> {
        Self::rings_with_wall(region, tool, step_over).0
    }

    /// Like [`Pocket::rings`], plus how many leading rings are the wall pass (the first offset).
    pub fn rings_with_wall(region: &Region, tool: &Tool, step_over: f64) -> (Vec<(Vec<Pt>, bool)>, usize) {
        let step = (tool.diameter * step_over.clamp(0.05, 1.0)).max(1e-3);
        let mut cur = region.offset(-tool.radius());
        let mut out = Vec::new();
        let mut wall = 0;
        let mut guard = 0;
        while !cur.is_empty() && guard < 10_000 {
            out.extend(cur.rings());
            if guard == 0 {
                wall = out.len();
            }
            cur = cur.offset(-step);
            guard += 1;
        }
        (out, wall)
    }
}

impl ToolpathStrategy for Pocket {
    fn generate(&self, geo: &Geometry, tool: &Tool, cut: &CutParams) -> Vec<Path3> {
        let levels = depth_levels(cut.depth, cut.step_down);
        let climb = cut.direction == Direction::Climb;
        let (mut rings, wall) = Self::rings_with_wall(&geo.region, tool, cut.step_over);
        if cut.dogbones {
            // only the wall pass touches the pocket's own corners; islands' corners are the pocket's reflex ones
            for (ring, _) in rings.iter_mut().take(wall).filter(|(_, hole)| !*hole) {
                *ring = add_dogbones(ring, tool.radius());
            }
        }
        let mut out = Vec::new();
        for (li, &z) in levels.iter().enumerate() {
            let z_before = if li == 0 { 0.0 } else { levels[li - 1] };
            for (ring, hole) in &rings {
                // climb inside a pocket: CW around the floor; islands (holes) are walked the other way
                let ring = orient_ring(ring.clone(), *hole == climb);
                out.extend(ring_passes_ex(&ring, &[z], cut.depth, None, cut.ramp_length, z_before));
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pocket_rings_shrink_until_empty_and_stay_inside() {
        let geo = Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [30., 0.], [30., 30.], [0., 30.]])]), lines: vec![] };
        let tool = Tool::end_mill(4.0);
        let rings = Pocket::rings(&geo.region, &tool, 0.5);
        assert!(rings.len() >= 6, "got {}", rings.len());
        for (r, _) in &rings {
            for p in r {
                assert!(p[0] >= 2.0 - 1e-3 && p[0] <= 28.0 + 1e-3);
            }
        }
        let paths = Pocket.generate(&geo, &tool, &CutParams { depth: 2.0, step_down: 1.0, step_over: 0.5, ..Default::default() });
        assert_eq!(paths.len(), rings.len() * 2);
        assert!(paths.iter().all(|p| !p.link));
    }

    #[test]
    fn pocket_around_an_island_never_enters_it() {
        let geo = Geometry {
            region: Region::from_outlines(&[
                Polyline::closed(vec![[0., 0.], [40., 0.], [40., 40.], [0., 40.]]),
                Polyline::closed(vec![[15., 15.], [25., 15.], [25., 25.], [15., 25.]]),
            ]),
            lines: vec![],
        };
        let tool = Tool::end_mill(3.0);
        for (ring, _) in Pocket::rings(&geo.region, &tool, 0.5) {
            for p in ring {
                let inside_island = p[0] > 15.0 + 1.5 - 1e-3 - 3.0 && p[0] < 25.0 - 1.5 + 1e-3 + 3.0 && p[1] > 13.5 - 1e-3 && p[1] < 26.5 + 1e-3;
                // tool centres must stay >= radius from the island wall
                let dx = (p[0] - 20.0).abs() - 5.0;
                let dy = (p[1] - 20.0).abs() - 5.0;
                let clear = if dx > 0.0 && dy > 0.0 { dx.hypot(dy) } else { dx.max(dy) };
                assert!(clear >= 1.5 - 1e-2, "centre {p:?} only {clear} from island ({inside_island})");
            }
        }
    }
}
