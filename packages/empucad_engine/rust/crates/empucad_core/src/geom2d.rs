//! 2D region operations. A [`Region`] is a set of polygons with holes.
use crate::types::{Polyline, Pt};
use i_overlay::core::fill_rule::FillRule;
use i_overlay::core::overlay_rule::OverlayRule;
use i_overlay::float::simplify::SimplifyShape;
use i_overlay::float::single::SingleFloatOverlay;
use i_overlay::mesh::outline::offset::OutlineOffset;
use i_overlay::mesh::style::{LineJoin, OutlineStyle};

/// Shape = outer contour first, then holes. Outer is CCW, holes are CW (normalised on construction).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Region {
    pub shapes: Vec<Vec<Vec<Pt>>>,
}

pub fn signed_area(pts: &[Pt]) -> f64 {
    let n = pts.len();
    let mut a = 0.0;
    for i in 0..n {
        let (p, q) = (pts[i], pts[(i + 1) % n]);
        a += p[0] * q[1] - q[0] * p[1];
    }
    a / 2.0
}

fn orient(mut c: Vec<Pt>, ccw: bool) -> Vec<Pt> {
    if (signed_area(&c) > 0.0) != ccw {
        c.reverse();
    }
    c
}

impl Region {
    fn from_raw(raw: Vec<Vec<Vec<Pt>>>) -> Self {
        let shapes = raw
            .into_iter()
            .filter(|s| !s.is_empty() && s[0].len() > 2)
            .map(|s| {
                s.into_iter()
                    .enumerate()
                    .map(|(i, c)| orient(c, i == 0))
                    .collect()
            })
            .collect();
        Self { shapes }
    }

    /// Union of closed outlines, interpreted with the even-odd rule per outline set
    /// (so a ring inside a ring becomes a hole, as in DabbleCAD's `regionFrom`).
    pub fn from_outlines(outlines: &[Polyline]) -> Self {
        let contours: Vec<Vec<Pt>> = outlines
            .iter()
            .filter(|p| p.closed && p.pts.len() > 2)
            .map(|p| p.pts.clone())
            .collect();
        if contours.is_empty() {
            return Self::default();
        }
        Self::from_raw(contours.simplify_shape(FillRule::EvenOdd))
    }

    pub fn is_empty(&self) -> bool {
        self.shapes.is_empty()
    }

    pub fn union(&self, other: &Region) -> Region {
        Self::from_raw(self.shapes.overlay(&other.shapes, OverlayRule::Union, FillRule::NonZero))
    }

    pub fn difference(&self, other: &Region) -> Region {
        Self::from_raw(self.shapes.overlay(&other.shapes, OverlayRule::Difference, FillRule::NonZero))
    }

    /// Grow (positive) or shrink (negative) by `delta` mm with rounded corners.
    pub fn offset(&self, delta: f64) -> Region {
        if self.is_empty() || delta.abs() < 1e-9 {
            return self.clone();
        }
        let style = OutlineStyle::new(delta).line_join(LineJoin::Round(0.25));
        Self::from_raw(self.shapes.outline(&style))
    }

    /// All contours flattened to closed polylines, outer rings CCW and holes CW.
    pub fn rings(&self) -> Vec<(Vec<Pt>, bool)> {
        let mut out = Vec::new();
        for s in &self.shapes {
            for (i, c) in s.iter().enumerate() {
                out.push((c.clone(), i > 0));
            }
        }
        out
    }

    pub fn area(&self) -> f64 {
        self.shapes
            .iter()
            .map(|s| s.iter().enumerate().map(|(i, c)| if i == 0 { signed_area(c).abs() } else { -signed_area(c).abs() }).sum::<f64>())
            .sum()
    }

    pub fn bounds(&self) -> Option<([f64; 2], [f64; 2])> {
        let mut it = self.shapes.iter().flatten().flatten();
        let first = it.next()?;
        let (mut lo, mut hi) = (*first, *first);
        for p in it {
            lo = [lo[0].min(p[0]), lo[1].min(p[1])];
            hi = [hi[0].max(p[0]), hi[1].max(p[1])];
        }
        Some((lo, hi))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_abs_diff_eq;

    fn square(x: f64, y: f64, s: f64) -> Polyline {
        Polyline::closed(vec![[x, y], [x + s, y], [x + s, y + s], [x, y + s]])
    }

    #[test]
    fn offset_grows_and_shrinks() {
        let r = Region::from_outlines(&[square(0.0, 0.0, 20.0)]);
        let (lo, hi) = r.offset(2.0).bounds().unwrap();
        assert_abs_diff_eq!(lo[0], -2.0, epsilon = 1e-3);
        assert_abs_diff_eq!(hi[0], 22.0, epsilon = 1e-3);
        let (lo, hi) = r.offset(-2.0).bounds().unwrap();
        assert_abs_diff_eq!(lo[0], 2.0, epsilon = 1e-3);
        assert_abs_diff_eq!(hi[0], 18.0, epsilon = 1e-3);
    }

    #[test]
    fn nested_outline_becomes_hole() {
        let r = Region::from_outlines(&[square(0.0, 0.0, 20.0), square(5.0, 5.0, 10.0)]);
        assert_eq!(r.shapes.len(), 1);
        assert_eq!(r.shapes[0].len(), 2);
        assert_abs_diff_eq!(r.area(), 400.0 - 100.0, epsilon = 1e-6);
    }

    #[test]
    fn union_merges_overlap() {
        let a = Region::from_outlines(&[square(0.0, 0.0, 10.0)]);
        let b = Region::from_outlines(&[square(5.0, 0.0, 10.0)]);
        assert_abs_diff_eq!(a.union(&b).area(), 150.0, epsilon = 1e-6);
    }

    #[test]
    fn shrink_past_empty_gives_empty() {
        let r = Region::from_outlines(&[square(0.0, 0.0, 4.0)]);
        assert!(r.offset(-3.0).is_empty());
    }
}
