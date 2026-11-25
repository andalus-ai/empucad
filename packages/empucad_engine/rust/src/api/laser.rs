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

pub fn plan_laser(shapes: Vec<LaserShapeSpec>, layers: Vec<LaserLayerSpec>, machine: LaserMachineSpec) -> Result<LaserResult, EngineApiError> {
    let mut core_shapes = Vec::new();
    for s in shapes {
        let mut outlines = Vec::new();
        for o in s.outlines {
            if o.points.len() % 2 != 0 {
                return Err(EngineApiError::invalid("outline points must be x,y pairs"));
            }
            outlines.push(Polyline { pts: o.points.chunks_exact(2).map(|c| [c[0], c[1]]).collect(), closed: o.closed });
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

#[derive(Debug, Clone, Copy)]
pub enum RasterModeSpec {
    Grayscale,
    Dither,
}

#[derive(Debug, Clone)]
pub struct RasterSpec {
    pub x: f64,
    pub y: f64,
    pub width_mm: f64,
    pub height_mm: f64,
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
    let s = RasterSettings {
        x: spec.x, y: spec.y, width_mm: spec.width_mm, height_mm: spec.height_mm, interval: spec.interval, speed: spec.speed,
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
        let spec = RasterSpec { x: 0., y: 0., width_mm: 4., height_mm: 1., interval: 1., speed: 100., power_min: 0., power_max: 80., bidirectional: true, overscan: 0., invert: false, mode: RasterModeSpec::Grayscale };
        let r = plan_raster_job(vec![0, 0, 255, 0], 4, 1, spec.clone(), m.clone()).unwrap();
        assert!(r.gcode.contains("S800"));
        assert!(plan_raster_job(vec![255; 4], 4, 1, spec, m).is_err());
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
