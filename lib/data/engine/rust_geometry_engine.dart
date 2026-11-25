import 'dart:typed_data';

import 'package:empucad_engine/empucad_engine.dart' as rust;

import '../../core/math/mat4.dart';
import '../../domain/entities/scene_node.dart';
import '../../domain/ports/geometry_engine.dart';

/// [GeometryEngine] backed by the Rust/Manifold plugin (`packages/empucad_engine`).
///
/// This is an adapter only: it converts between domain types and the flutter_rust_bridge types and
/// maps engine errors to [EngineFailure]. All geometry work happens in Rust.
final class RustGeometryEngine implements GeometryEngine {
  const RustGeometryEngine({this.segments = 64});

  /// Facets per full circle for cylinders, cones and spheres.
  final int segments;

  @override
  Future<MeshData> primitive(ShapeKind kind, {required double width, required double depth, required double height}) async {
    final rust.MeshData m = switch (kind) {
      ShapeKind.box => rust.makeBox(x: width, y: depth, z: height),
      ShapeKind.cylinder => rust.makeCylinder(height: height, radiusBottom: width / 2, radiusTop: width / 2, segments: segments),
      ShapeKind.cone => rust.makeCylinder(height: height, radiusBottom: width / 2, radiusTop: 0, segments: segments),
      ShapeKind.sphere => rust.makeSphere(radius: width / 2, segments: segments),
    };
    return _fromRust(m);
  }

  @override
  Future<MeshData> boolean({required List<MeshData> solids, required List<MeshData> holes, required BooleanMode mode}) => _guard(() async {
        final out = await rust.booleanOp(
          solids: solids.map(_toRust).toList(),
          holes: holes.map(_toRust).toList(),
          mode: mode == BooleanMode.union ? rust.BoolMode.union : rust.BoolMode.intersect,
        );
        return _fromRust(out);
      });

  @override
  Future<MeshData> transform(MeshData mesh, Mat4 matrix) =>
      _guard(() async => _fromRust(await rust.transformMesh(mesh: _toRust(mesh), matrix: Float64List.fromList(matrix.toAffine12()))));

  @override
  Future<SolidReport> inspect(MeshData mesh) async {
    final r = await rust.inspectMesh(mesh: _toRust(mesh));
    return SolidReport(closed: r.closed, volume: r.volume, surfaceArea: r.surfaceArea);
  }

  @override
  Future<Uint8List> encodeStl(MeshData mesh) => rust.stlEncode(mesh: _toRust(mesh));

  @override
  Future<MeshData> decodeStl(Uint8List bytes) => _guard(() async => _fromRust(await rust.stlDecode(bytes: bytes)));

  static rust.MeshData _toRust(MeshData m) => rust.MeshData(positions: m.positions, indices: m.indices);
  static MeshData _fromRust(rust.MeshData m) => MeshData(m.positions, m.indices);

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on rust.EngineApiError catch (e) {
      throw switch (e.kind) {
        rust.ErrorKind.notWatertight => NotWatertightFailure(e.detail),
        rust.ErrorKind.emptyResult => const EmptyResultFailure(),
        rust.ErrorKind.invalidInput || rust.ErrorKind.stl => InvalidInputFailure(e.detail),
      };
    }
  }
}
