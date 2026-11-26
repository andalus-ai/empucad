use super::error::EngineApiError;
use empucad_core::cam::*;
use empucad_core::gcode::{self, Output, Post, Program, Section};
use empucad_core::geom2d::Region;
use empucad_core::types::Polyline;

/// Outline points are flat x,y pairs in millimetres.
#[derive(Debug, Clone)]
pub struct Outline {
    pub points: Vec<f64>,
    pub closed: bool,
}

/// The outlines of ONE design shape (outer ring plus its holes, even-odd).
/// Separate shapes are unioned, so overlapping shapes merge instead of cancelling.
#[derive(Debug, Clone)]
pub struct ShapeOutlines {
    pub outlines: Vec<Outline>,
}

#[derive(Debug, Clone, Copy)]
pub enum ToolpathKind {
    ProfileOutside,
    ProfileInside,
    ProfileOn,
    Pocket,
    Engrave,
    Drill,
}

/// One tool + operation. A job is an ordered list of these.
#[derive(Debug, Clone)]
pub struct OperationSpec {
    pub name: String,
    pub tool_number: u32,
    pub tool_diameter: f64,
    pub kind: ToolpathKind,
    pub shapes: Vec<ShapeOutlines>,
    pub depth: f64,
    pub step_down: f64,
    /// Fraction of tool diameter, (0, 1].
    pub step_over: f64,
    pub climb: bool,
    pub feed: f64,
    pub plunge: f64,
    pub rpm: f64,
    /// 0 = no tabs. Profiles only.
    pub tab_count: u32,
    pub tab_width: f64,
    pub tab_height: f64,
    /// 0 = plunge straight down.
    pub ramp_length: f64,
}

#[derive(Debug, Clone)]
pub struct CamJobSpec {
    pub operations: Vec<OperationSpec>,
    /// One of `list_posts()` ids.
    pub post_id: String,
    pub inches: bool,
    pub safe_z: f64,
    pub clear_z: f64,
    pub rapid_rate: f64,
    /// Emit G2/G3 arcs where runs of cuts lie on a circle.
    pub arcs: bool,
}

#[derive(Debug, Clone)]
pub struct CamResult {
    pub gcode: String,
    pub file_extension: String,
    pub seconds: f64,
    /// x, y, z, rapid(1|0) per move, for drawing the toolpath.
    pub preview: Vec<f32>,
}

#[derive(Debug, Clone)]
pub struct PostInfo {
    pub id: String,
    pub name: String,
    pub extension: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_posts() -> Vec<PostInfo> {
    gcode::POSTS.iter().map(|p| PostInfo { id: p.id.into(), name: p.name.into(), extension: p.ext.into() }).collect()
}

fn polylines(o: &[Outline]) -> Result<Vec<Polyline>, EngineApiError> {
    o.iter()
        .map(|o| {
            if o.points.len() % 2 != 0 {
                return Err(EngineApiError::invalid("outline points must be x,y pairs"));
            }
            Ok(Polyline { pts: o.points.chunks_exact(2).map(|c| [c[0], c[1]]).collect(), closed: o.closed })
        })
        .collect()
}

fn strategy(kind: ToolpathKind) -> Box<dyn ToolpathStrategy> {
    match kind {
        ToolpathKind::ProfileOutside => Box::new(Profile { side: Side::Outside }),
        ToolpathKind::ProfileInside => Box::new(Profile { side: Side::Inside }),
        ToolpathKind::ProfileOn => Box::new(Profile { side: Side::On }),
        ToolpathKind::Pocket => Box::new(Pocket),
        ToolpathKind::Engrave => Box::new(Engrave),
        ToolpathKind::Drill => Box::new(Drill),
    }
}

pub fn generate_cam(job: CamJobSpec) -> Result<CamResult, EngineApiError> {
    let post = Post::by_id(&job.post_id).ok_or_else(|| EngineApiError::invalid(format!("unknown post '{}'", job.post_id)))?;
    let mut sections = Vec::new();
    for op in &job.operations {
        if op.tool_diameter <= 0.0 || op.depth <= 0.0 {
            return Err(EngineApiError::invalid(format!("'{}': tool diameter and depth must be positive", op.name)));
        }
        let mut lines = Vec::new();
        let mut region = Region::default();
        for shape in &op.shapes {
            let pl = polylines(&shape.outlines)?;
            region = region.union(&Region::from_outlines(&pl));
            lines.extend(pl);
        }
        let geo = Geometry { region, lines };
        let tool = Tool::end_mill(op.tool_diameter);
        let cut = CutParams {
            depth: op.depth,
            step_down: op.step_down,
            step_over: op.step_over,
            direction: if op.climb { Direction::Climb } else { Direction::Conventional },
            tabs: (op.tab_count > 0).then_some(Tabs { count: op.tab_count, width: op.tab_width, height: op.tab_height }),
            ramp_length: op.ramp_length.max(0.0),
        };
        sections.push(Section {
            name: op.name.clone(),
            tool_number: op.tool_number,
            feed: op.feed,
            plunge: op.plunge,
            rpm: op.rpm,
            paths: strategy(op.kind).generate(&geo, &tool, &cut),
        });
    }
    let program = Program { sections };
    let mut out = Output::new(post);
    out.inches = job.inches;
    out.safe_z = job.safe_z;
    out.clear_z = job.clear_z;
    out.rapid_rate = job.rapid_rate;
    out.arcs = job.arcs;
    Ok(CamResult {
        gcode: gcode::write(&program, &out),
        file_extension: post.ext.into(),
        seconds: gcode::estimate_seconds(&program, &out),
        preview: gcode::preview(&program, &out),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::error::ErrorKind;

    fn square() -> Outline {
        Outline { points: vec![0., 0., 20., 0., 20., 20., 0., 20.], closed: true }
    }

    fn job(kind: ToolpathKind) -> CamJobSpec {
        CamJobSpec {
            operations: vec![OperationSpec {
                name: "op".into(), tool_number: 1, tool_diameter: 3.0, kind, shapes: vec![ShapeOutlines { outlines: vec![square()] }],
                depth: 2.0, step_down: 1.0, step_over: 0.45, climb: true, feed: 800.0, plunge: 300.0, rpm: 12000.0,
                tab_count: 0, tab_width: 0.0, tab_height: 0.0, ramp_length: 0.0,
            }],
            post_id: "grbl".into(), inches: false, safe_z: 5.0, clear_z: 1.0, rapid_rate: 3000.0, arcs: false,
        }
    }

    #[test]
    fn every_kind_produces_gcode_and_preview() {
        for k in [ToolpathKind::ProfileOutside, ToolpathKind::ProfileInside, ToolpathKind::ProfileOn, ToolpathKind::Pocket, ToolpathKind::Engrave, ToolpathKind::Drill] {
            let r = generate_cam(job(k)).unwrap();
            assert!(r.gcode.contains("M3 S12000"), "{k:?}");
            assert!(!r.preview.is_empty() && r.seconds > 0.0, "{k:?}");
            assert_eq!(r.file_extension, "gcode");
        }
    }

    #[test]
    fn validation_errors_are_typed() {
        let mut j = job(ToolpathKind::Pocket);
        j.post_id = "nope".into();
        assert!(matches!(generate_cam(j), Err(e) if e.kind == ErrorKind::InvalidInput));
        let mut j = job(ToolpathKind::Pocket);
        j.operations[0].shapes[0].outlines[0].points.pop();
        assert!(matches!(generate_cam(j), Err(e) if e.kind == ErrorKind::InvalidInput));
        let mut j = job(ToolpathKind::Pocket);
        j.operations[0].depth = 0.0;
        assert!(generate_cam(j).is_err());
    }

    #[test]
    fn overlapping_shapes_merge_instead_of_cancelling() {
        // two 20 mm squares overlapping by 10 mm; outside profile must be ONE outline spanning 30 mm
        let mut j = job(ToolpathKind::ProfileOutside);
        j.operations[0].depth = 1.0;
        j.operations[0].shapes = vec![
            ShapeOutlines { outlines: vec![square()] },
            ShapeOutlines { outlines: vec![Outline { points: vec![10., 0., 30., 0., 30., 20., 10., 20.], closed: true }] },
        ];
        let r = generate_cam(j).unwrap();
        // every separate contour starts with a rapid down to clear height (z = 1.0); depth == step
        // gives one level, so this counts contours. Merged = 1; XOR'd overlap would give 2.
        let contours = r.preview.chunks_exact(4).filter(|m| m[3] == 1.0 && m[2] == 1.0).count();
        assert_eq!(contours, 1);
        let xs: Vec<f32> = r.preview.chunks_exact(4).filter(|m| m[3] == 0.0).map(|m| m[0]).collect();
        let (lo, hi) = (xs.iter().cloned().fold(f32::MAX, f32::min), xs.iter().cloned().fold(f32::MIN, f32::max));
        assert!((lo + 1.5).abs() < 1e-2 && (hi - 31.5).abs() < 1e-2, "{lo} {hi}");
    }

    #[test]
    fn tabs_and_ramp_flow_through_to_the_gcode() {
        let mut j = job(ToolpathKind::ProfileOutside);
        j.operations[0].depth = 3.0;
        j.operations[0].tab_count = 4;
        j.operations[0].tab_width = 6.0;
        j.operations[0].tab_height = 1.0;
        let tabbed = generate_cam(j.clone()).unwrap();
        // tab top is z = -2: the deepest pass must visit both -3 and -2
        let zs: Vec<f32> = tabbed.preview.chunks_exact(4).filter(|m| m[3] == 0.0).map(|m| m[2]).collect();
        assert!(zs.contains(&-3.0) && zs.contains(&-2.0));
        let mut plain = j.clone();
        plain.operations[0].tab_count = 0;
        assert!(tabbed.gcode.len() > generate_cam(plain).unwrap().gcode.len(), "tabs add moves");

        let mut r = j;
        r.operations[0].tab_count = 0;
        r.operations[0].ramp_length = 10.0;
        let ramped = generate_cam(r).unwrap();
        // a ramp has no vertical plunge segments after the first approach: no cut move changes z with fixed xy
        let cuts: Vec<&[f32]> = ramped.preview.chunks_exact(4).filter(|m| m[3] == 0.0).collect();
        let vertical_plunges = cuts.windows(2).filter(|w| w[0][0] == w[1][0] && w[0][1] == w[1][1] && w[1][2] < w[0][2] - 0.5).count();
        assert_eq!(vertical_plunges, 0);
    }

    #[test]
    fn arcs_option_turns_rounded_corners_into_g3_and_shortens_the_program() {
        let plain = generate_cam(job(ToolpathKind::ProfileOutside)).unwrap();
        assert!(!plain.gcode.lines().any(|l| l.starts_with("G2 ") || l.starts_with("G3 ")));
        let mut j = job(ToolpathKind::ProfileOutside);
        j.arcs = true;
        let arcs = generate_cam(j).unwrap();
        // outside + climb is counter-clockwise: four rounded corners per level
        assert!(arcs.gcode.lines().filter(|l| l.starts_with("G3 ")).count() >= 4, "{}", arcs.gcode);
        assert!(arcs.gcode.lines().count() < plain.gcode.lines().count());
        // the preview still traces the same outline: x stays within the offset square
        let xs: Vec<f32> = arcs.preview.chunks_exact(4).filter(|m| m[3] == 0.0).map(|m| m[0]).collect();
        assert!(xs.iter().all(|&x| (-1.51..=21.51).contains(&x)));
    }

    #[test]
    fn posts_are_listed() {
        assert_eq!(list_posts().len(), 5);
    }
}
