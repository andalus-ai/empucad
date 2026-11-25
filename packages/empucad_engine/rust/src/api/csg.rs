use super::cam::Outline;
use super::error::EngineApiError;
use empucad_core::csg::{self, BoolMode as CoreMode};
use empucad_core::{stl, types::Mesh};

/// Indexed triangle mesh: `positions` = x,y,z triples, `indices` = triangle triples.
#[derive(Debug, Clone)]
pub struct MeshData {
    pub positions: Vec<f32>,
    pub indices: Vec<u32>,
}

#[derive(Debug, Clone, Copy)]
pub enum BoolMode {
    Union,
    Intersect,
}

#[derive(Debug, Clone, Copy)]
pub struct SolidReport {
    pub closed: bool,
    pub volume: f64,
    pub surface_area: f64,
}

impl From<MeshData> for Mesh {
    fn from(m: MeshData) -> Self {
        Mesh { positions: m.positions, indices: m.indices }
    }
}
impl From<Mesh> for MeshData {
    fn from(m: Mesh) -> Self {
        MeshData { positions: m.positions, indices: m.indices }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn make_box(x: f64, y: f64, z: f64) -> MeshData {
    csg::cuboid(x, y, z).into()
}

#[flutter_rust_bridge::frb(sync)]
pub fn make_cylinder(height: f64, radius_bottom: f64, radius_top: f64, segments: i32) -> MeshData {
    csg::cylinder(height, radius_bottom, radius_top, segments).into()
}

#[flutter_rust_bridge::frb(sync)]
pub fn make_sphere(radius: f64, segments: i32) -> MeshData {
    csg::sphere(radius, segments).into()
}

/// `solids` are combined (union or intersection) and the union of `holes` is subtracted.
/// Heavy: runs on a Rust worker thread, returns a Future in Dart.
pub fn boolean_op(solids: Vec<MeshData>, holes: Vec<MeshData>, mode: BoolMode) -> Result<MeshData, EngineApiError> {
    let solids: Vec<Mesh> = solids.into_iter().map(Into::into).collect();
    let holes: Vec<Mesh> = holes.into_iter().map(Into::into).collect();
    let mode = match mode {
        BoolMode::Union => CoreMode::Union,
        BoolMode::Intersect => CoreMode::Intersect,
    };
    Ok(csg::boolean(&solids, &holes, mode)?.into())
}

/// `matrix` is 12 numbers, column-major 3x4 (x basis, y basis, z basis, translation).
pub fn transform_mesh(mesh: MeshData, matrix: Vec<f64>) -> Result<MeshData, EngineApiError> {
    let m: [f64; 12] = matrix
        .try_into()
        .map_err(|v: Vec<f64>| EngineApiError::invalid(format!("matrix needs 12 numbers, got {}", v.len())))?;
    Ok(csg::transform(&mesh.into(), &m)?.into())
}

/// Extrude one design shape's outlines (outer ring plus holes) from z = 0 up to `height`.
pub fn extrude_outlines(outlines: Vec<Outline>, height: f64) -> Result<MeshData, EngineApiError> {
    let mut pl = Vec::new();
    for o in outlines {
        if o.points.len() % 2 != 0 {
            return Err(EngineApiError::invalid("outline points must be x,y pairs"));
        }
        pl.push(empucad_core::types::Polyline { pts: o.points.chunks_exact(2).map(|c| [c[0], c[1]]).collect(), closed: o.closed });
    }
    Ok(csg::extrude(&pl, height)?.into())
}

pub fn inspect_mesh(mesh: MeshData) -> SolidReport {
    let r = csg::inspect(&mesh.into());
    SolidReport { closed: r.closed, volume: r.volume, surface_area: r.surface_area }
}

pub fn stl_encode(mesh: MeshData) -> Vec<u8> {
    stl::write_binary(&mesh.into())
}

pub fn stl_decode(bytes: Vec<u8>) -> Result<MeshData, EngineApiError> {
    Ok(stl::read(&bytes)?.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::error::ErrorKind;

    #[test]
    fn drill_then_stl_roundtrip() {
        let out = boolean_op(vec![make_box(20., 20., 20.)], vec![make_cylinder(30., 5., 5., 64)], BoolMode::Union).unwrap();
        let back = stl_decode(stl_encode(out.clone())).unwrap();
        assert!(inspect_mesh(back).closed);
        assert!(inspect_mesh(out).volume < 8000.0);
    }

    #[test]
    fn extrude_makes_a_closed_solid() {
        let o = Outline { points: vec![0., 0., 10., 0., 10., 10., 0., 10.], closed: true };
        let m = extrude_outlines(vec![o], 4.0).unwrap();
        let r = inspect_mesh(m);
        assert!(r.closed && (r.volume - 400.0).abs() < 1e-3);
        assert!(extrude_outlines(vec![Outline { points: vec![0., 0., 1.], closed: true }], 1.0).is_err());
    }

    #[test]
    fn bad_matrix_length_is_a_typed_error() {
        let e = transform_mesh(make_box(1., 1., 1.), vec![1.0; 5]).unwrap_err();
        assert!(e.kind == ErrorKind::InvalidInput);
    }
}
