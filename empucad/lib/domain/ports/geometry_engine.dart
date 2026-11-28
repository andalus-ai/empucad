import 'dart:typed_data';

import '../../core/math/mat4.dart';
import '../entities/mesh_data.dart';
import '../entities/outline.dart';

export '../entities/mesh_data.dart';
import '../entities/scene_node.dart';

final class SolidReport {
  const SolidReport({required this.closed, required this.volume, required this.surfaceArea});
  final bool closed;
  final double volume, surfaceArea;
}

enum BooleanMode { union, intersect }

/// Why the engine refused. Sealed so callers handle every case.
sealed class EngineFailure implements Exception {
  const EngineFailure(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

final class NotWatertightFailure extends EngineFailure {
  const NotWatertightFailure(super.message);
}

final class InvalidInputFailure extends EngineFailure {
  const InvalidInputFailure(super.message);
}

final class EmptyResultFailure extends EngineFailure {
  const EmptyResultFailure() : super('boolean produced an empty result');
}

/// 3D kernel port. The app depends on this interface only; the Rust/Manifold adapter lives in `data/`.
abstract interface class GeometryEngine {
  /// A centred primitive. Round kinds use `width` as the diameter.
  Future<MeshData> primitive(ShapeKind kind, {required double width, required double depth, required double height});

  /// Combine `solids` (union or intersection), then subtract the union of `holes`.
  Future<MeshData> boolean({required List<MeshData> solids, required List<MeshData> holes, required BooleanMode mode});

  /// Extrude one shape's outlines from z = 0 up to `height`. Nested outlines become holes.
  Future<MeshData> extrude(List<Outline> outlines, double height);

  Future<MeshData> transform(MeshData mesh, Mat4 matrix);
  Future<SolidReport> inspect(MeshData mesh);
  Future<Uint8List> encodeStl(MeshData mesh);
  Future<MeshData> decodeStl(Uint8List bytes);
}
