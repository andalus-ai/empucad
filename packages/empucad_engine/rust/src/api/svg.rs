use super::cam::{Outline, ShapeOutlines};
use super::error::EngineApiError;
use empucad_core::svg::{svg_to_gcode, SvgOptions as CoreOpts};
use empucad_core::svg_import::import_svg;

#[derive(Debug, Clone)]
pub struct SvgConvertOptions {
    pub feedrate: f64,
    pub tolerance: f64,
    pub dpi: f64,
    pub circular_interpolation: bool,
    pub tool_on: String,
    pub tool_off: String,
}

/// SVG text -> G-code via the `svg2gcode` crate.
pub fn convert_svg(svg: String, options: SvgConvertOptions) -> Result<String, EngineApiError> {
    let o = CoreOpts {
        feedrate: options.feedrate,
        tolerance: options.tolerance,
        dpi: options.dpi,
        circular_interpolation: options.circular_interpolation,
        tool_on: options.tool_on,
        tool_off: options.tool_off,
        ..CoreOpts::default()
    };
    Ok(svg_to_gcode(&svg, &o)?)
}

#[derive(Debug, Clone)]
pub struct SvgImportResult {
    pub shapes: Vec<ShapeOutlines>,
    pub width_mm: f64,
    pub height_mm: f64,
}

/// Parse an SVG into flat outlines in millimetres (Y up). Curves are flattened to `tolerance_mm`.
pub fn import_svg_shapes(svg: String, tolerance_mm: f64) -> Result<SvgImportResult, EngineApiError> {
    let r = import_svg(&svg, tolerance_mm)?;
    Ok(SvgImportResult {
        width_mm: r.width_mm,
        height_mm: r.height_mm,
        shapes: r
            .shapes
            .into_iter()
            .map(|s| ShapeOutlines {
                outlines: s.outlines.into_iter().map(|p| Outline { points: p.pts.iter().flat_map(|q| [q[0], q[1]]).collect(), closed: p.closed }).collect(),
            })
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn imports_shapes_as_flat_xy_pairs() {
        let svg = r#"<svg xmlns="http://www.w3.org/2000/svg" width="20mm" height="20mm" viewBox="0 0 20 20"><rect x="2" y="2" width="6" height="6"/></svg>"#;
        let r = import_svg_shapes(svg.into(), 0.05).unwrap();
        assert_eq!(r.shapes.len(), 1);
        assert_eq!(r.shapes[0].outlines[0].points.len(), 8);
        assert!(import_svg_shapes("nope".into(), 0.05).is_err());
    }

    #[test]
    fn converts() {
        let svg = r#"<svg xmlns="http://www.w3.org/2000/svg" width="10mm" height="10mm" viewBox="0 0 10 10"><path d="M1 1 L9 9"/></svg>"#;
        let g = convert_svg(svg.into(), SvgConvertOptions { feedrate: 500., tolerance: 0.02, dpi: 96., circular_interpolation: true, tool_on: "M3 S800".into(), tool_off: "M5".into() }).unwrap();
        assert!(g.contains("M3 S800") && g.contains("F500"));
    }
}
