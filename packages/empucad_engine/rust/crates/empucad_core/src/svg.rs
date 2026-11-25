//! SVG -> G-code through the existing `svg2gcode` crate (feature `svg`).
//!
//! This is the fast path for pen plotters and simple laser line work. DabbleCAD's layered laser
//! planner ([`crate::laser`]) is used when per-layer speed/power/fill matter.
use crate::error::{EngineError, Result};
use g_code::emit::{format_gcode_fmt, FormatOptions};
use g_code::parse::{ast::Snippet, snippet_parser};
use svg2gcode::{svg2program, ConversionConfig, ConversionOptions, Machine, SupportedFunctionality};

#[derive(Clone, Debug, PartialEq)]
pub struct SvgOptions {
    /// mm/min
    pub feedrate: f64,
    /// Curve flattening tolerance, mm.
    pub tolerance: f64,
    pub dpi: f64,
    /// Emit G2/G3 arcs instead of line segments.
    pub circular_interpolation: bool,
    pub tool_on: String,
    pub tool_off: String,
    pub begin: String,
    pub end: String,
}

impl Default for SvgOptions {
    fn default() -> Self {
        Self {
            feedrate: 1000.0,
            tolerance: 0.02,
            dpi: 96.0,
            circular_interpolation: true,
            tool_on: "M4 S500".into(),
            tool_off: "M5".into(),
            begin: "G21\nG90".into(),
            end: "M2".into(),
        }
    }
}

fn snip(s: &str) -> Result<Snippet<'_>> {
    snippet_parser(s).map_err(|e| EngineError::InvalidInput(format!("G-code snippet {s:?}: {e}")))
}

pub fn svg_to_gcode(svg: &str, o: &SvgOptions) -> Result<String> {
    let doc = roxmltree::Document::parse(svg).map_err(|e| EngineError::InvalidInput(format!("SVG: {e}")))?;
    let machine = Machine::new(
        SupportedFunctionality { circular_interpolation: o.circular_interpolation },
        Some(snip(&o.tool_on)?),
        Some(snip(&o.tool_off)?),
        Some(snip(&o.begin)?),
        Some(snip(&o.end)?),
    );
    let cfg = ConversionConfig { feedrate: o.feedrate, tolerance: o.tolerance, dpi: o.dpi, ..Default::default() };
    let tokens = svg2program(&doc, &cfg, ConversionOptions::default(), machine);
    let mut out = String::new();
    format_gcode_fmt(tokens.iter(), FormatOptions::default(), &mut out).map_err(|e| EngineError::InvalidInput(e.to_string()))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SQUARE: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" width="20mm" height="20mm" viewBox="0 0 20 20"><path d="M2 2 H18 V18 H2 Z"/></svg>"#;

    #[test]
    fn converts_a_square_path() {
        let g = svg_to_gcode(SQUARE, &SvgOptions::default()).unwrap();
        assert!(g.contains("G21"), "{g}");
        assert!(g.contains("M4 S500") && g.contains("M5"));
        assert!(g.contains("G1") && g.contains("F1000"), "{g}");
    }

    #[test]
    fn bad_svg_is_an_error_not_a_panic() {
        assert!(matches!(svg_to_gcode("<svg", &SvgOptions::default()), Err(EngineError::InvalidInput(_))));
    }
}
