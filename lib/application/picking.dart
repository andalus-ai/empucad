import 'dart:math' as math;

import '../core/math/vec3.dart';
import 'scene_evaluator.dart';

final class PickHit {
  const PickHit(this.nodeId, this.distance);
  final String nodeId;
  final double distance;
}

/// CPU ray picking against evaluated meshes (Moeller-Trumbore). Renderer-independent, so it works
/// the same with flutter_scene or the canvas fallback.
abstract final class Picker {
  /// Nearest solid hit, or null. Holes are pickable too (so they can be selected and toggled).
  static PickHit? pick(Ray ray, List<RenderItem> items) {
    PickHit? best;
    for (final item in items) {
      final t = _nearest(ray, item);
      if (t != null && (best == null || t < best.distance)) best = PickHit(item.nodeId, t);
    }
    return best;
  }

  static double? _nearest(Ray ray, RenderItem item) {
    final p = item.mesh.positions;
    final idx = item.mesh.indices;
    if (!_hitsBounds(ray, p)) return null;
    double? best;
    for (var i = 0; i + 2 < idx.length; i += 3) {
      final a = idx[i] * 3, b = idx[i + 1] * 3, c = idx[i + 2] * 3;
      final t = _tri(ray, p[a], p[a + 1], p[a + 2], p[b], p[b + 1], p[b + 2], p[c], p[c + 1], p[c + 2]);
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }

  static bool _hitsBounds(Ray r, List<double> p) {
    if (p.isEmpty) return false;
    var lo = [double.infinity, double.infinity, double.infinity];
    var hi = [-double.infinity, -double.infinity, -double.infinity];
    for (var i = 0; i + 2 < p.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        lo[k] = math.min(lo[k], p[i + k]);
        hi[k] = math.max(hi[k], p[i + k]);
      }
    }
    final o = [r.origin.x, r.origin.y, r.origin.z];
    final d = [r.direction.x, r.direction.y, r.direction.z];
    var t0 = 0.0, t1 = double.infinity;
    for (var k = 0; k < 3; k++) {
      if (d[k].abs() < 1e-12) {
        if (o[k] < lo[k] || o[k] > hi[k]) return false;
      } else {
        var a = (lo[k] - o[k]) / d[k], b = (hi[k] - o[k]) / d[k];
        if (a > b) (a, b) = (b, a);
        t0 = math.max(t0, a);
        t1 = math.min(t1, b);
        if (t0 > t1) return false;
      }
    }
    return true;
  }

  static double? _tri(Ray r, double ax, double ay, double az, double bx, double by, double bz, double cx, double cy, double cz) {
    final e1 = Vec3(bx - ax, by - ay, bz - az), e2 = Vec3(cx - ax, cy - ay, cz - az);
    final h = r.direction.cross(e2);
    final det = e1.dot(h);
    if (det.abs() < 1e-12) return null; // parallel; both faces are pickable
    final f = 1 / det;
    final s = r.origin - Vec3(ax, ay, az);
    final u = f * s.dot(h);
    if (u < 0 || u > 1) return null;
    final q = s.cross(e1);
    final v = f * r.direction.dot(q);
    if (v < 0 || u + v > 1) return null;
    final t = f * e2.dot(q);
    return t > 1e-9 ? t : null;
  }
}
