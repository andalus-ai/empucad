//! SVG paths -> flat outlines (mm), via `usvg` (which resolves transforms, units, `use`, and turns
//! arcs into curves). Text is not imported (the `text` feature is off, so no font stack is pulled in).
use crate::error::{EngineError, Result};
use crate::types::{Polyline, Pt};
use usvg::tiny_skia_path::{PathSegment, Point};

/// One SVG `<path>`/shape: its subpaths together form one region (holes by even-odd).
#[derive(Clone, Debug, PartialEq)]
pub struct ImportedShape {
    pub outlines: Vec<Polyline>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SvgImport {
    pub shapes: Vec<ImportedShape>,
    pub width_mm: f64,
    pub height_mm: f64,
}

const PX_TO_MM: f64 = 25.4 / 96.0;

/// `tolerance_mm` bounds the chord error when flattening curves.
pub fn import_svg(svg: &str, tolerance_mm: f64) -> Result<SvgImport> {
    let tree = usvg::Tree::from_str(svg, &usvg::Options::default()).map_err(|e| EngineError::InvalidInput(format!("SVG: {e}")))?;
    let h_px = tree.size().height() as f64;
    let tol_px = (tolerance_mm / PX_TO_MM).max(1e-4);
    let mut shapes = Vec::new();
    walk(tree.root(), h_px, tol_px, &mut shapes);
    Ok(SvgImport { shapes, width_mm: tree.size().width() as f64 * PX_TO_MM, height_mm: h_px * PX_TO_MM })
}

fn walk(g: &usvg::Group, h_px: f64, tol: f64, out: &mut Vec<ImportedShape>) {
    for node in g.children() {
        match node {
            usvg::Node::Group(c) => walk(c, h_px, tol, out),
            usvg::Node::Path(p) if p.is_visible() => {
                let filled = p.fill().is_some();
                let t = p.abs_transform();
                let map = |pt: Point| -> Pt {
                    let mut q = pt;
                    t.map_point(&mut q);
                    [q.x as f64 * PX_TO_MM, (h_px - q.y as f64) * PX_TO_MM]
                };
                let mut outlines = Vec::new();
                let mut cur: Vec<Pt> = Vec::new();
                let mut start = Point::zero();
                let mut last = Point::zero();
                let flush = |cur: &mut Vec<Pt>, closed: bool, outlines: &mut Vec<Polyline>| {
                    if cur.len() > 1 {
                        let closed = closed || filled; // a fill closes open subpaths implicitly
                        let mut pts = std::mem::take(cur);
                        if closed && pts.len() > 2 && pts.first() == pts.last() {
                            pts.pop();
                        }
                        if !closed || pts.len() > 2 {
                            outlines.push(Polyline { pts, closed });
                        }
                    } else {
                        cur.clear();
                    }
                };
                for seg in p.data().segments() {
                    match seg {
                        PathSegment::MoveTo(pt) => {
                            flush(&mut cur, false, &mut outlines);
                            start = pt;
                            last = pt;
                            cur.push(map(pt));
                        }
                        PathSegment::LineTo(pt) => {
                            cur.push(map(pt));
                            last = pt;
                        }
                        PathSegment::QuadTo(c, pt) => {
                            let (c1, c2) = (lerp(last, c, 2.0 / 3.0), lerp(pt, c, 2.0 / 3.0));
                            flatten_cubic(last, c1, c2, pt, tol, 0, &mut |q| cur.push(map(q)));
                            last = pt;
                        }
                        PathSegment::CubicTo(c1, c2, pt) => {
                            flatten_cubic(last, c1, c2, pt, tol, 0, &mut |q| cur.push(map(q)));
                            last = pt;
                        }
                        PathSegment::Close => {
                            flush(&mut cur, true, &mut outlines);
                            last = start;
                        }
                    }
                }
                flush(&mut cur, false, &mut outlines);
                if !outlines.is_empty() {
                    out.push(ImportedShape { outlines });
                }
            }
            _ => {}
        }
    }
}

fn lerp(a: Point, b: Point, t: f32) -> Point {
    Point::from_xy(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
}

/// Adaptive de Casteljau: emits the end point of every flat-enough piece (not the start point).
fn flatten_cubic(p0: Point, p1: Point, p2: Point, p3: Point, tol: f64, depth: u32, emit: &mut impl FnMut(Point)) {
    let dist = |p: Point| -> f64 {
        let (dx, dy) = ((p3.x - p0.x) as f64, (p3.y - p0.y) as f64);
        let len = dx.hypot(dy);
        if len < 1e-9 {
            return ((p.x - p0.x) as f64).hypot((p.y - p0.y) as f64);
        }
        (((p.x - p0.x) as f64) * dy - ((p.y - p0.y) as f64) * dx).abs() / len
    };
    if depth >= 16 || (dist(p1) <= tol && dist(p2) <= tol) {
        emit(p3);
        return;
    }
    let (a, b, c) = (lerp(p0, p1, 0.5), lerp(p1, p2, 0.5), lerp(p2, p3, 0.5));
    let (d, e) = (lerp(a, b, 0.5), lerp(b, c, 0.5));
    let m = lerp(d, e, 0.5);
    flatten_cubic(p0, a, d, m, tol, depth + 1, emit);
    flatten_cubic(m, e, c, p3, tol, depth + 1, emit);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geom2d::{signed_area, Region};

    fn svg(body: &str) -> String {
        format!(r#"<svg xmlns="http://www.w3.org/2000/svg" width="20mm" height="20mm" viewBox="0 0 20 20">{body}</svg>"#)
    }

    #[test]
    fn square_is_20mm_and_y_is_flipped_to_cad_up() {
        let r = import_svg(&svg(r#"<path d="M2 2 H12 V6 H2 Z"/>"#), 0.01).unwrap();
        assert!((r.width_mm - 20.0).abs() < 1e-3 && (r.height_mm - 20.0).abs() < 1e-3);
        let o = &r.shapes[0].outlines[0];
        assert!(o.closed && o.pts.len() == 4);
        let ys: Vec<f64> = o.pts.iter().map(|p| p[1]).collect();
        // SVG y 2..6 (down) is CAD y 14..18 (up) on a 20 mm page
        assert!((ys.iter().cloned().fold(f64::MAX, f64::min) - 14.0).abs() < 1e-3);
        assert!((ys.iter().cloned().fold(f64::MIN, f64::max) - 18.0).abs() < 1e-3);
    }

    #[test]
    fn circle_area_matches_and_finer_tolerance_gives_more_points() {
        let c = svg(r#"<circle cx="10" cy="10" r="5"/>"#);
        let coarse = import_svg(&c, 0.5).unwrap();
        let fine = import_svg(&c, 0.005).unwrap();
        let (a, b) = (&coarse.shapes[0].outlines[0], &fine.shapes[0].outlines[0]);
        assert!(b.pts.len() > a.pts.len());
        let area = signed_area(&b.pts).abs();
        assert!((area - std::f64::consts::PI * 25.0).abs() < 0.2, "{area}");
    }

    #[test]
    fn subpaths_of_one_path_make_a_region_with_a_hole() {
        let r = import_svg(&svg(r#"<path fill-rule="evenodd" d="M0 0 H10 V10 H0 Z M3 3 H7 V7 H3 Z"/>"#), 0.01).unwrap();
        assert_eq!(r.shapes.len(), 1);
        assert_eq!(r.shapes[0].outlines.len(), 2);
        let region = Region::from_outlines(&r.shapes[0].outlines);
        assert!((region.area() - 84.0).abs() < 1e-3);
    }

    #[test]
    fn stroke_only_line_stays_open_and_transforms_apply() {
        let r = import_svg(&svg(r#"<g transform="translate(5 0)"><path fill="none" stroke="black" d="M0 10 L10 10"/></g>"#), 0.01).unwrap();
        let o = &r.shapes[0].outlines[0];
        assert!(!o.closed);
        assert!((o.pts[0][0] - 5.0).abs() < 1e-3 && (o.pts[1][0] - 15.0).abs() < 1e-3);
    }

    #[test]
    fn garbage_is_an_error() {
        assert!(import_svg("not svg", 0.1).is_err());
    }
}
