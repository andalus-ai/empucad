//! Flutter bridge for the EmpuCAD engine. Adapters only: convert FRB-friendly flat data into
//! `empucad_core` types and back. No geometry or CAM logic belongs here.
pub mod api;
// flutter_rust_bridge_codegen injects `mod frb_generated;` below on first `generate`.
