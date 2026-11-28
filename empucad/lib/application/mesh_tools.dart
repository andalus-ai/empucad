import 'dart:typed_data';

import '../domain/entities/mesh_data.dart';

/// Pure mesh helpers.
abstract final class MeshTools {
  /// Moves the mesh so it is centred in X and Y with its lowest point on z = 0, the way every built-in
  /// shape sits on the workplane. Returns a new mesh; the input is not modified.
  static MeshData restOnWorkplane(MeshData m) {
    final p = m.positions;
    if (p.length < 3) return m;
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity, minZ = double.infinity;
    for (var i = 0; i + 2 < p.length; i += 3) {
      if (p[i] < minX) minX = p[i];
      if (p[i] > maxX) maxX = p[i];
      if (p[i + 1] < minY) minY = p[i + 1];
      if (p[i + 1] > maxY) maxY = p[i + 1];
      if (p[i + 2] < minZ) minZ = p[i + 2];
    }
    final dx = -(minX + maxX) / 2, dy = -(minY + maxY) / 2, dz = -minZ;
    final out = Float32List(p.length);
    for (var i = 0; i + 2 < p.length; i += 3) {
      out[i] = p[i] + dx;
      out[i + 1] = p[i + 1] + dy;
      out[i + 2] = p[i + 2] + dz;
    }
    return MeshData(out, m.indices);
  }

  /// Convex hull of 2D points given as flat x,y pairs, counter-clockwise, without a repeated end point.
  /// Andrew's monotone chain, O(n log n). Fewer than 3 distinct points give back what is there.
  static List<double> convexHull(List<double> xy) {
    final pts = <(double, double)>[for (var i = 0; i + 1 < xy.length; i += 2) (xy[i], xy[i + 1])]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final uniq = <(double, double)>[];
    for (final p in pts) {
      if (uniq.isEmpty || uniq.last != p) uniq.add(p);
    }
    if (uniq.length < 3) return [for (final p in uniq) ...[p.$1, p.$2]];
    double cross((double, double) o, (double, double) a, (double, double) b) => (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);
    final hull = <(double, double)>[];
    for (final p in uniq) {
      while (hull.length >= 2 && cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    final lower = hull.length + 1;
    for (var i = uniq.length - 2; i >= 0; i--) {
      final p = uniq[i];
      while (hull.length >= lower && cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    hull.removeLast();
    return [for (final p in hull) ...[p.$1, p.$2]];
  }
}
