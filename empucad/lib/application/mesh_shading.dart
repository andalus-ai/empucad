import 'dart:math' as math;
import 'dart:typed_data';

import '../core/math/vec3.dart';
import '../domain/ports/geometry_engine.dart';
import 'scene_evaluator.dart';

/// Un-indexed vertices with one normal per triangle, for crisp CAD-style flat shading.
/// (Kernel output shares vertices between faces, so auto-smoothed normals would round every edge.)
final class FlatMesh {
  const FlatMesh(this.positions, this.normals);
  final Float32List positions;
  final Float32List normals;
  int get vertexCount => positions.length ~/ 3;
}

abstract final class MeshShading {
  static FlatMesh flat(MeshData m) {
    final n = m.indices.length;
    final pos = Float32List(n * 3), nrm = Float32List(n * 3);
    for (var t = 0; t + 2 < n; t += 3) {
      final ia = m.indices[t] * 3, ib = m.indices[t + 1] * 3, ic = m.indices[t + 2] * 3;
      final a = Vec3(m.positions[ia], m.positions[ia + 1], m.positions[ia + 2]);
      final b = Vec3(m.positions[ib], m.positions[ib + 1], m.positions[ib + 2]);
      final c = Vec3(m.positions[ic], m.positions[ic + 1], m.positions[ic + 2]);
      final f = (b - a).cross(c - a).normalized();
      for (var k = 0; k < 3; k++) {
        final p = [a, b, c][k];
        final o = (t + k) * 3;
        pos[o] = p.x;
        pos[o + 1] = p.y;
        pos[o + 2] = p.z;
        nrm[o] = f.x;
        nrm[o + 1] = f.y;
        nrm[o + 2] = f.z;
      }
    }
    return FlatMesh(pos, nrm);
  }
}

/// Axis-aligned bounds of everything drawable.
abstract final class SceneBounds {
  static (Vec3, Vec3)? of(Iterable<RenderItem> items) {
    var lo = const Vec3(double.infinity, double.infinity, double.infinity);
    var hi = const Vec3(-double.infinity, -double.infinity, -double.infinity);
    var any = false;
    for (final i in items) {
      final p = i.mesh.positions;
      for (var k = 0; k + 2 < p.length; k += 3) {
        any = true;
        lo = Vec3(math.min(lo.x, p[k]), math.min(lo.y, p[k + 1]), math.min(lo.z, p[k + 2]));
        hi = Vec3(math.max(hi.x, p[k]), math.max(hi.y, p[k + 1]), math.max(hi.z, p[k + 2]));
      }
    }
    return any ? (lo, hi) : null;
  }
}
