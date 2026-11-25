use super::*;

/// Follow the lines themselves (open or closed) at depth.
pub struct Engrave;

impl ToolpathStrategy for Engrave {
    fn generate(&self, geo: &Geometry, _tool: &Tool, cut: &CutParams) -> Vec<Path3> {
        let levels = depth_levels(cut.depth, cut.step_down);
        let mut out = Vec::new();
        for line in geo.lines.iter().filter(|l| l.pts.len() > 1) {
            for (i, &z) in levels.iter().enumerate() {
                let mut pts: Vec<Pt> = line.pts.clone();
                if line.closed {
                    pts.push(pts[0]);
                } else if i % 2 == 1 {
                    pts.reverse(); // zig-zag open lines so deeper passes need no retract
                }
                out.push(Path3 { pts: pts.iter().map(|p| [p[0], p[1], z]).collect(), link: i > 0 });
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn open_line_zigzags_between_passes() {
        let geo = Geometry { region: Region::default(), lines: vec![Polyline::open(vec![[0., 0.], [10., 0.]])] };
        let p = Engrave.generate(&geo, &Tool::end_mill(1.0), &CutParams { depth: 2.0, step_down: 1.0, ..Default::default() });
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].pts[0][0], 0.0);
        assert_eq!(p[1].pts[0][0], 10.0);
        assert!(p[1].link);
    }
}
