//! Watertight 3D booleans on the same Manifold kernel DabbleCAD uses (there via WASM).
use crate::error::{EngineError, Result};
use crate::types::Mesh;
use crate::geom2d::Region;
use crate::types::Polyline;
use manifold_csg::{CrossSection, FillRule, Manifold, MeshGL};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BoolMode {
    Union,
    Intersect,
}

/// 3x4 affine transform, column-major (matches `Manifold::transform`).
pub type Affine = [f64; 12];

pub const IDENTITY: Affine = [1., 0., 0., 0., 1., 0., 0., 0., 1., 0., 0., 0.];

fn to_manifold(m: &Mesh) -> Result<Manifold> {
    if m.indices.len() < 12 {
        return Err(EngineError::NotWatertight("fewer than 4 triangles".into()));
    }
    let gl = MeshGL::new(&m.positions, 3, &m.indices)
        .map_err(|e| EngineError::NotWatertight(e.to_string()))?
        .merge(); // weld duplicate vertices from triangle soups
    let man = Manifold::from_meshgl(&gl).map_err(|e| EngineError::NotWatertight(e.to_string()))?;
    if man.is_empty() {
        return Err(EngineError::NotWatertight("empty after welding".into()));
    }
    Ok(man)
}

fn from_manifold(m: &Manifold) -> Mesh {
    let (positions, n_props, indices) = m.to_mesh_f32();
    if n_props == 3 {
        return Mesh { positions, indices };
    }
    let mut p = Vec::with_capacity(positions.len() / n_props * 3);
    for v in positions.chunks_exact(n_props) {
        p.extend_from_slice(&v[..3]);
    }
    Mesh { positions: p, indices }
}

pub fn transform(mesh: &Mesh, m: &Affine) -> Result<Mesh> {
    Ok(from_manifold(&to_manifold(mesh)?.transform(m)))
}

/// Mirrors `solidBoolean`: combine `solids` (union or intersection), then subtract the union of `holes`.
/// Fails with [`EngineError::NotWatertight`] if any operand is not a closed solid, so callers can
/// fall back to a different path exactly as the Electron app does.
pub fn boolean(solids: &[Mesh], holes: &[Mesh], mode: BoolMode) -> Result<Mesh> {
    let s: Vec<Manifold> = solids.iter().map(to_manifold).collect::<Result<_>>()?;
    let h: Vec<Manifold> = holes.iter().map(to_manifold).collect::<Result<_>>()?;
    let cut = if h.is_empty() { None } else { Some(Manifold::batch_union(&h)) };
    let body = match (s.len(), mode) {
        (0, _) => cut.clone().ok_or_else(|| EngineError::InvalidInput("no operands".into()))?,
        (1, _) => s.into_iter().next().unwrap(),
        (_, BoolMode::Union) => Manifold::batch_union(&s),
        (_, BoolMode::Intersect) => s[1..].iter().fold(s[0].clone(), |a, b| a.intersection(b)),
    };
    let result = match (&cut, solids.is_empty()) {
        (Some(c), false) => body.difference(c),
        _ => body,
    };
    result.status().map_err(|e| EngineError::NotWatertight(e.to_string()))?;
    if result.is_empty() {
        return Err(EngineError::EmptyResult);
    }
    Ok(from_manifold(&result))
}

pub fn cuboid(x: f64, y: f64, z: f64) -> Mesh {
    from_manifold(&Manifold::cube(x, y, z, true))
}
/// Cylinder along Z, centred. `r_top` != `r_bottom` gives a cone frustum.
pub fn cylinder(height: f64, r_bottom: f64, r_top: f64, segments: i32) -> Mesh {
    from_manifold(&Manifold::cylinder(height, r_bottom, r_top, segments, true))
}
pub fn sphere(radius: f64, segments: i32) -> Mesh {
    from_manifold(&Manifold::sphere(radius, segments))
}

/// Extrude closed outlines straight up from z = 0 to `height`. Nested outlines become holes
/// (even-odd), so letters and rings extrude correctly. Fails on an empty or zero-area result.
pub fn extrude(outlines: &[Polyline], height: f64) -> Result<Mesh> {
    if height <= 0.0 || !height.is_finite() {
        return Err(EngineError::InvalidInput("extrude height must be positive".into()));
    }
    let region = Region::from_outlines(outlines);
    if region.is_empty() {
        return Err(EngineError::InvalidInput("no closed outline to extrude".into()));
    }
    let polys: Vec<Vec<[f64; 2]>> = region.rings().into_iter().map(|(r, _)| r).collect();
    let cs = CrossSection::from_polygons_with_fill_rule(&polys, FillRule::EvenOdd);
    let m = Manifold::extrude(&cs, height);
    if m.is_empty() {
        return Err(EngineError::EmptyResult);
    }
    Ok(from_manifold(&m))
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SolidReport {
    pub closed: bool,
    pub volume: f64,
    pub surface_area: f64,
}

/// Is this mesh a closed solid, and how big is it? (DabbleCAD's `inspectSolid`.)
pub fn inspect(mesh: &Mesh) -> SolidReport {
    match to_manifold(mesh) {
        Ok(m) => SolidReport { closed: true, volume: m.volume(), surface_area: m.surface_area() },
        Err(_) => SolidReport { closed: false, volume: 0.0, surface_area: 0.0 },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_relative_eq;

    #[test]
    fn drilling_a_cube_removes_cylinder_volume() {
        let cube = cuboid(20., 20., 20.);
        let hole = cylinder(30., 5., 5., 128);
        let out = boolean(&[cube], &[hole], BoolMode::Union).unwrap();
        let r = inspect(&out);
        assert!(r.closed);
        // cylinder through the cube: pi r^2 h, 128-gon approximation
        let cyl = 0.5 * 128.0 * 25.0 * (2.0 * std::f64::consts::PI / 128.0).sin() * 20.0;
        assert_relative_eq!(r.volume, 8000.0 - cyl, epsilon = 1.0);
    }

    #[test]
    fn intersection_of_overlapping_cubes() {
        let a = cuboid(10., 10., 10.);
        let b = transform(&cuboid(10., 10., 10.), &[1., 0., 0., 0., 1., 0., 0., 0., 1., 5., 0., 0.]).unwrap();
        let out = boolean(&[a, b], &[], BoolMode::Intersect).unwrap();
        assert_relative_eq!(inspect(&out).volume, 500.0, epsilon = 1e-3);
    }

    #[test]
    fn union_of_overlapping_cubes() {
        let a = cuboid(10., 10., 10.);
        let b = transform(&cuboid(10., 10., 10.), &[1., 0., 0., 0., 1., 0., 0., 0., 1., 5., 0., 0.]).unwrap();
        let out = boolean(&[a, b], &[], BoolMode::Union).unwrap();
        assert_relative_eq!(inspect(&out).volume, 1500.0, epsilon = 1e-3);
    }

    #[test]
    fn extrude_square_and_ring() {
        let sq = |x: f64, s: f64| Polyline::closed(vec![[x, x], [x + s, x], [x + s, x + s], [x, x + s]]);
        let solid = extrude(&[sq(0., 10.)], 5.0).unwrap();
        assert_relative_eq!(inspect(&solid).volume, 500.0, epsilon = 1e-3);
        let ring = extrude(&[sq(0., 10.), sq(2., 6.)], 5.0).unwrap(); // 10x10 with a 6x6 hole
        assert_relative_eq!(inspect(&ring).volume, (100.0 - 36.0) * 5.0, epsilon = 1e-3);
        assert!(extrude(&[], 5.0).is_err());
        assert!(extrude(&[sq(0., 10.)], 0.0).is_err());
        assert!(extrude(&[Polyline::open(vec![[0., 0.], [1., 1.]])], 1.0).is_err());
    }

    #[test]
    fn open_mesh_is_rejected_not_panicked() {
        // a single triangle fan is not a closed solid
        let m = Mesh { positions: vec![0., 0., 0., 1., 0., 0., 0., 1., 0.], indices: vec![0, 1, 2] };
        assert!(matches!(boolean(std::slice::from_ref(&m), &[], BoolMode::Union), Err(EngineError::NotWatertight(_))));
        assert!(!inspect(&m).closed);
    }
}
