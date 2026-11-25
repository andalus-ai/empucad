import 'dart:typed_data';

import 'package:empucad/core/math/mat4.dart';
import 'package:empucad/domain/entities/outline.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/ports/geometry_engine.dart';

/// In-memory engine for tests: real cube meshes, real transforms, recorded boolean calls.
/// Booleans just concatenate meshes (enough to check orchestration, not CSG maths).
final class FakeGeometryEngine implements GeometryEngine {
  final List<({int solids, int holes, BooleanMode mode})> booleanCalls = [];
  int primitiveCalls = 0;
  int transformCalls = 0;

  /// When set, `boolean` throws this.
  EngineFailure? failBooleanWith;

  static const _corners = [
    [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
    [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],
  ];
  static const _tris = [
    0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
    2, 3, 7, 2, 7, 6, 1, 2, 6, 1, 6, 5, 3, 0, 4, 3, 4, 7,
  ];

  @override
  Future<MeshData> primitive(ShapeKind kind, {required double width, required double depth, required double height}) async {
    primitiveCalls++;
    final p = <double>[];
    for (final c in _corners) {
      p..add(c[0] * width / 2)..add(c[1] * depth / 2)..add(c[2] * height / 2);
    }
    return MeshData(Float32List.fromList(p), Uint32List.fromList(_tris));
  }

  int extrudeCalls = 0;

  /// Extrudes the bounding box of the closed outlines (enough to check placement and plumbing).
  @override
  Future<MeshData> extrude(List<Outline> outlines, double height) async {
    extrudeCalls++;
    final closed = outlines.where((o) => o.closed && o.points.length >= 6).toList();
    if (closed.isEmpty) throw const InvalidInputFailure('no closed outline to extrude');
    var lox = double.infinity, loy = double.infinity, hix = -double.infinity, hiy = -double.infinity;
    for (final o in closed) {
      for (var i = 0; i + 1 < o.points.length; i += 2) {
        lox = lox < o.points[i] ? lox : o.points[i];
        hix = hix > o.points[i] ? hix : o.points[i];
        loy = loy < o.points[i + 1] ? loy : o.points[i + 1];
        hiy = hiy > o.points[i + 1] ? hiy : o.points[i + 1];
      }
    }
    final p = <double>[];
    for (final c in _corners) {
      p..add(c[0] < 0 ? lox : hix)..add(c[1] < 0 ? loy : hiy)..add(c[2] < 0 ? 0 : height);
    }
    return MeshData(Float32List.fromList(p), Uint32List.fromList(_tris));
  }

  @override
  Future<MeshData> transform(MeshData mesh, Mat4 matrix) async {
    transformCalls++;
    final out = Float32List(mesh.positions.length);
    for (var i = 0; i < out.length; i += 3) {
      final r = matrix.transformPoint(mesh.positions[i], mesh.positions[i + 1], mesh.positions[i + 2]);
      out[i] = r.x;
      out[i + 1] = r.y;
      out[i + 2] = r.z;
    }
    return MeshData(out, mesh.indices);
  }

  @override
  Future<MeshData> boolean({required List<MeshData> solids, required List<MeshData> holes, required BooleanMode mode}) async {
    booleanCalls.add((solids: solids.length, holes: holes.length, mode: mode));
    final fail = failBooleanWith;
    if (fail != null) throw fail;
    final pos = <double>[];
    final idx = <int>[];
    for (final m in solids) {
      final base = pos.length ~/ 3;
      pos.addAll(m.positions);
      idx.addAll(m.indices.map((i) => i + base));
    }
    return MeshData(Float32List.fromList(pos), Uint32List.fromList(idx));
  }

  @override
  Future<SolidReport> inspect(MeshData mesh) async => const SolidReport(closed: true, volume: 0, surfaceArea: 0);
  @override
  Future<Uint8List> encodeStl(MeshData mesh) async => Uint8List(0);
  @override
  Future<MeshData> decodeStl(Uint8List bytes) async => MeshData(Float32List(0), Uint32List(0));
}
