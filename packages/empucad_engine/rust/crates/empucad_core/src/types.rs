/// A 2D point in millimetres.
pub type Pt = [f64; 2];
/// A 3D point in millimetres.
pub type Pt3 = [f64; 3];

/// An open or closed 2D polyline.
#[derive(Clone, Debug, PartialEq)]
pub struct Polyline {
    pub pts: Vec<Pt>,
    pub closed: bool,
}

impl Polyline {
    pub fn closed(pts: Vec<Pt>) -> Self {
        Self { pts, closed: true }
    }
    pub fn open(pts: Vec<Pt>) -> Self {
        Self { pts, closed: false }
    }
}

/// Indexed triangle mesh. `positions` is x,y,z triples; `indices` is triangle triples.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Mesh {
    pub positions: Vec<f32>,
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn vertex_count(&self) -> usize {
        self.positions.len() / 3
    }
    pub fn triangle_count(&self) -> usize {
        self.indices.len() / 3
    }
    pub fn is_empty(&self) -> bool {
        self.indices.is_empty()
    }
    /// Axis-aligned bounds as (min, max).
    pub fn bounds(&self) -> Option<([f32; 3], [f32; 3])> {
        if self.positions.is_empty() {
            return None;
        }
        let mut lo = [f32::MAX; 3];
        let mut hi = [f32::MIN; 3];
        for v in self.positions.chunks_exact(3) {
            for k in 0..3 {
                lo[k] = lo[k].min(v[k]);
                hi[k] = hi[k].max(v[k]);
            }
        }
        Some((lo, hi))
    }
}

/// One continuous cutter path in job coordinates (Z = 0 is the top of the stock, cuts are negative).
#[derive(Clone, Debug, PartialEq)]
pub struct Path3 {
    pub pts: Vec<Pt3>,
    /// True when the cutter may stay down and link straight from the previous path.
    pub link: bool,
}
