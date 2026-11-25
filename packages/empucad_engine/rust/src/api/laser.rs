use super::cam::Outline;
use super::error::EngineApiError;
use empucad_core::laser::{self, Flavor, LaserLayer, LaserShape, LayerMode, Machine};
use empucad_core::raster::{plan_raster, RasterMode, RasterSettings};
use empucad_core::types::Polyline;

#[derive(Debug, Clone, Copy)]
pub enum LayerModeSpec {
    Line,
    Fill,
}

#[derive(Debug, Clone)]
pub struct LaserLayerSpec {
    pub index: u32,
    pub mode: LayerModeSpec,
    /// mm/s
    pub speed: f64,
    /// percent
    pub power: f64,
    pub passes: u32,
    pub interval: f64,
    pub angle: f64,
    pub bidirectional: bool,
    pub overscan: f64,
}

#[derive(Debug, Clone)]
pub struct LaserShapeSpec {
    pub layer: u32,
    pub outlines: Vec<Outline>,
}

#[derive(Debug, Clone)]
pub struct LaserMachineSpec {
    pub bed_w: f64,
    pub bed_h: f64,
    pub s_max: f64,
    pub rapid: f64,
    /// true = `M4` dynamic power, false = `M3` constant power.
    pub dynamic_power: bool,
}

#[derive(Debug, Clone)]
pub struct LaserResult {
    pub gcode: String,
    pub seconds: f64,
}

/// Shapes are in MACHINE coordinates (origin bottom-left, Y up), the same as the G-code that comes
/// back. The core planner works in a top-left, Y-down design space, so Y is converted here.
pub fn plan_laser(shapes: Vec<LaserShapeSpec>, layers: Vec<LaserLayerSpec>, machine: LaserMachineSpec) -> Result<LaserResult, EngineApiError> {
    let bed_h = machine.bed_h;
    let mut core_shapes = Vec::new();
    for s in shapes {
        let mut outlines = Vec::new();
        for o in s.outlines {
            if o.points.len() % 2 != 0 {
                return Err(EngineApiError::invalid("outline points must be x,y pairs"));
            }
            outlines.push(Polyline { pts: o.points.chunks_exact(2).map(|c| [c[0], bed_h - c[1]]).collect(), closed: o.closed });
        }
        core_shapes.push(LaserShape { layer: s.layer as usize, outlines });
    }
    let core_layers: Vec<LaserLayer> = layers
        .into_iter()
        .map(|l| LaserLayer {
            index: l.index as usize,
            mode: match l.mode { LayerModeSpec::Line => LayerMode::Line, LayerModeSpec::Fill => LayerMode::Fill },
            speed: l.speed, power: l.power, passes: l.passes, interval: l.interval, angle: l.angle,
            bidirectional: l.bidirectional, overscan: l.overscan,
        })
        .collect();
    let m = Machine {
        bed_w: machine.bed_w, bed_h: machine.bed_h, s_max: machine.s_max, rapid: machine.rapid,
        flavor: if machine.dynamic_power { Flavor::GrblDynamic } else { Flavor::GrblConstant },
    };
    let job = laser::plan(&core_shapes, &core_layers, &m);
    Ok(LaserResult { gcode: job.gcode, seconds: job.seconds })
}

/// x, y, power(S), rapid(1|0) per move, for drawing any laser G-code.
pub fn preview_laser_gcode(gcode: String) -> Vec<f32> {
    laser::preview_gcode(&gcode)
}

#[derive(Debug, Clone, Copy)]
pub enum RasterModeSpec {
    Grayscale,
    Dither,
}

/// `x`,`y` is the image's BOTTOM-LEFT corner in machine coordinates (Y up). Height follows from the
/// image's aspect ratio.
#[derive(Debug, Clone)]
pub struct RasterSpec {
    pub x: f64,
    pub y: f64,
    pub width_mm: f64,
    pub interval: f64,
    pub speed: f64,
    pub power_min: f64,
    pub power_max: f64,
    pub bidirectional: bool,
    pub overscan: f64,
    pub invert: bool,
    pub mode: RasterModeSpec,
}

/// `gray` is width*height 8-bit pixels, row-major, top row first, 0 = black.
pub fn plan_raster_job(gray: Vec<u8>, width: u32, height: u32, spec: RasterSpec, machine: LaserMachineSpec) -> Result<LaserResult, EngineApiError> {
    if width == 0 || height == 0 {
        return Err(EngineApiError::invalid("image has no pixels"));
    }
    let height_mm = spec.width_mm * height as f64 / width as f64;
    let s = RasterSettings {
        // core wants the top-left corner in Y-down design space
        x: spec.x, y: machine.bed_h - (spec.y + height_mm), width_mm: spec.width_mm, height_mm, interval: spec.interval, speed: spec.speed,
        power_min: spec.power_min, power_max: spec.power_max, bidirectional: spec.bidirectional, overscan: spec.overscan, invert: spec.invert,
        mode: match spec.mode { RasterModeSpec::Grayscale => RasterMode::Grayscale, RasterModeSpec::Dither => RasterMode::Dither },
    };
    let m = Machine {
        bed_w: machine.bed_w, bed_h: machine.bed_h, s_max: machine.s_max, rapid: machine.rapid,
        flavor: if machine.dynamic_power { Flavor::GrblDynamic } else { Flavor::GrblConstant },
    };
    let job = plan_raster(&gray, width, height, &s, &m)?;
    Ok(LaserResult { gcode: job.gcode, seconds: job.seconds })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plans_a_raster_job_and_rejects_a_blank_image() {
        let m = LaserMachineSpec { bed_w: 100., bed_h: 100., s_max: 1000., rapid: 6000., dynamic_power: true };
        let spec = RasterSpec { x: 0., y: 0., width_mm: 4., interval: 1., speed: 100., power_min: 0., power_max: 80., bidirectional: true, overscan: 0., invert: false, mode: RasterModeSpec::Grayscale };
        let r = plan_raster_job(vec![0, 0, 255, 0], 4, 1, spec.clone(), m.clone()).unwrap();
        assert!(r.gcode.contains("S800"));
        assert!(plan_raster_job(vec![255; 4], 4, 1, spec, m).is_err());
    }

    #[test]
    fn machine_y_in_is_machine_y_out_for_vector_layers() {
        // 20 mm square with its bottom-left at (10, 10) on a 100 mm tall bed: the G-code must visit
        // exactly those machine coordinates, not a mirrored copy.
        let r = plan_laser(
            vec![LaserShapeSpec { layer: 0, outlines: vec![Outline { points: vec![10., 10., 30., 10., 30., 30., 10., 30.], closed: true }] }],
            vec![LaserLayerSpec { index: 0, mode: LayerModeSpec::Line, speed: 10., power: 50., passes: 1, interval: 0.1, angle: 0., bidirectional: true, overscan: 0. }],
            LaserMachineSpec { bed_w: 100., bed_h: 100., s_max: 1000., rapid: 6000., dynamic_power: true },
        )
        .unwrap();
        assert!(r.gcode.contains("G0 X10 Y10"), "{}", r.gcode);
        let mv = empucad_core::laser::preview_gcode(&r.gcode);
        // the last move is the footer's `G0 X0 Y0` return to origin, not part of the shape
        let ys: Vec<f32> = mv.chunks_exact(4).rev().skip(1).map(|m| m[1]).collect();
        assert!(ys.iter().all(|&y| (10.0..=30.0).contains(&y)), "{ys:?}");
        assert!(ys.contains(&30.0));
    }

    #[test]
    fn raster_is_placed_by_its_bottom_left_corner_with_the_top_row_on_top() {
        let m = LaserMachineSpec { bed_w: 100., bed_h: 100., s_max: 1000., rapid: 6000., dynamic_power: true };
        // 2 px wide, 2 px tall, 4 mm wide => 4 mm tall, interval 2 => two lines, at y = 10 + 3 and 10 + 1
        let spec = RasterSpec { x: 20., y: 10., width_mm: 4., interval: 2., speed: 100., power_min: 0., power_max: 100., bidirectional: false, overscan: 0., invert: false, mode: RasterModeSpec::Grayscale };
        // top row black, bottom row white: only the TOP line burns
        let r = plan_raster_job(vec![0, 0, 255, 255], 2, 2, spec, m).unwrap();
        let burn_ys: Vec<f32> = empucad_core::laser::preview_gcode(&r.gcode).chunks_exact(4).filter(|v| v[2] > 0.0).map(|v| v[1]).collect();
        assert!(!burn_ys.is_empty() && burn_ys.iter().all(|&y| (y - 13.0).abs() < 1e-3), "{burn_ys:?}");
        let xs: Vec<f32> = empucad_core::laser::preview_gcode(&r.gcode).chunks_exact(4).filter(|v| v[2] > 0.0).map(|v| v[0]).collect();
        assert!(xs.iter().all(|&x| (20.0..=24.0).contains(&x)));
    }

    #[test]
    fn plans_a_line_layer() {
        let r = plan_laser(
            vec![LaserShapeSpec { layer: 0, outlines: vec![Outline { points: vec![0., 0., 10., 0., 10., 10., 0., 10.], closed: true }] }],
            vec![LaserLayerSpec { index: 0, mode: LayerModeSpec::Line, speed: 10., power: 50., passes: 1, interval: 0.1, angle: 0., bidirectional: true, overscan: 2.5 }],
            LaserMachineSpec { bed_w: 100., bed_h: 100., s_max: 1000., rapid: 6000., dynamic_power: true },
        )
        .unwrap();
        assert!(r.gcode.contains("S500") && r.gcode.contains("M4"));
    }
}
