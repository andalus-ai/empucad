//! EmpuCAD core engine.
//!
//! Pure Rust, no Flutter dependency, so every piece is unit-testable on its own.
//! The Flutter plugin crate (`../../empucad_bridge`) is a thin adapter over this crate.
//!
//! Module responsibilities (one reason to change each):
//! * [`types`]  - plain data shared across modules (points, meshes, paths)
//! * [`geom2d`] - 2D polygon union / offset (i_overlay)
//! * [`csg`]    - watertight 3D booleans and primitives (Manifold, via manifold-csg)
//! * [`stl`]    - STL import / export
//! * [`cam`]    - toolpath strategies (profile, pocket, engrave, drill)
//! * [`gcode`]  - machine moves, post-processors, time estimate
//! * [`laser`]  - laser layers, fills and GRBL laser output
pub mod cam;
pub mod csg;
pub mod error;
pub mod gcode;
pub mod geom2d;
pub mod laser;
pub mod raster;
pub mod stl;
#[cfg(feature = "svg")]
pub mod svg;
#[cfg(feature = "svg")]
pub mod svg_import;
pub mod types;

pub use error::EngineError;
