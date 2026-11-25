use super::*;

/// Drill at the centre of each outer shape. With `step_down < depth` it pecks.
pub struct Drill;

impl ToolpathStrategy for Drill {
    fn generate(&self, geo: &Geometry, _tool: &Tool, cut: &CutParams) -> Vec<Path3> {
        let levels = depth_levels(cut.depth, cut.step_down);
        geo.region
            .shapes
            .iter()
            .map(|s| {
                let (lo, hi) = s[0].iter().fold(([f64::MAX; 2], [f64::MIN; 2]), |(lo, hi), p| ([lo[0].min(p[0]), lo[1].min(p[1])], [hi[0].max(p[0]), hi[1].max(p[1])]));
                let (x, y) = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0);
                let mut pts = Vec::new();
                for (i, &z) in levels.iter().enumerate() {
                    pts.push([x, y, z]);
                    if i + 1 < levels.len() {
                        pts.push([x, y, 0.0]); // retract to clear chips
                    }
                }
                Path3 { pts, link: false }
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pecks_at_shape_centre() {
        let geo = Geometry { region: Region::from_outlines(&[Polyline::closed(vec![[0., 0.], [4., 0.], [4., 4.], [0., 4.]])]), lines: vec![] };
        let p = Drill.generate(&geo, &Tool::end_mill(2.0), &CutParams { depth: 6.0, step_down: 3.0, ..Default::default() });
        assert_eq!(p.len(), 1);
        assert_eq!(p[0].pts, vec![[2., 2., -3.], [2., 2., 0.], [2., 2., -6.]]);
    }
}
