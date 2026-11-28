import '../core/math/mat4.dart';
import '../domain/entities/scene_node.dart';

/// Axis-aligned box in world space (mm).
final class Bounds {
  const Bounds(this.minX, this.maxX, this.minY, this.maxY, this.minZ, this.maxZ);
  final double minX, maxX, minY, maxY, minZ, maxZ;

  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get width => maxX - minX;
  double get depth => maxY - minY;
  double get height => maxZ - minZ;

  Bounds union(Bounds o) => Bounds(
        minX < o.minX ? minX : o.minX, maxX > o.maxX ? maxX : o.maxX,
        minY < o.minY ? minY : o.minY, maxY > o.maxY ? maxY : o.maxY,
        minZ < o.minZ ? minZ : o.minZ, maxZ > o.maxZ ? maxZ : o.maxZ,
      );

  /// The box of the 8 corners of a local box after `m`. Conservative for rotated shapes.
  static Bounds ofBox(Mat4 m, double x0, double x1, double y0, double y1, double z0, double z1) {
    var lox = double.infinity, loy = double.infinity, loz = double.infinity;
    var hix = -double.infinity, hiy = -double.infinity, hiz = -double.infinity;
    for (final x in [x0, x1]) {
      for (final y in [y0, y1]) {
        for (final z in [z0, z1]) {
          final p = m.transformPoint(x, y, z);
          if (p.x < lox) lox = p.x;
          if (p.x > hix) hix = p.x;
          if (p.y < loy) loy = p.y;
          if (p.y > hiy) hiy = p.y;
          if (p.z < loz) loz = p.z;
          if (p.z > hiz) hiz = p.z;
        }
      }
    }
    return Bounds(lox, hix, loy, hiy, loz, hiz);
  }
}

/// World-space bounds of a node, including its placement and any groups above it.
/// Round shapes use their bounding box; rotated shapes get the box of their rotated bounding box.
abstract final class NodeBounds {
  static Bounds? of(SceneNode n, [Mat4? parent]) {
    final m = (parent ?? Mat4.identity) * n.placement.toMatrix();
    switch (n) {
      case ShapeNode():
        return Bounds.ofBox(m, -n.width / 2, n.width / 2, -n.depth / 2, n.depth / 2, 0, n.height);
      case OutlineNode():
        var lox = double.infinity, loy = double.infinity, hix = -double.infinity, hiy = -double.infinity;
        for (final o in n.shapes.expand((s) => s.outlines)) {
          for (var i = 0; i + 1 < o.points.length; i += 2) {
            if (o.points[i] < lox) lox = o.points[i];
            if (o.points[i] > hix) hix = o.points[i];
            if (o.points[i + 1] < loy) loy = o.points[i + 1];
            if (o.points[i + 1] > hiy) hiy = o.points[i + 1];
          }
        }
        return lox.isFinite ? Bounds.ofBox(m, lox, hix, loy, hiy, 0, n.height) : null;
      case MeshNode():
        final p = n.mesh.positions;
        if (p.length < 3) return null;
        var lox = double.infinity, loy = double.infinity, loz = double.infinity, hix = -double.infinity, hiy = -double.infinity, hiz = -double.infinity;
        for (var i = 0; i + 2 < p.length; i += 3) {
          if (p[i] < lox) lox = p[i].toDouble();
          if (p[i] > hix) hix = p[i].toDouble();
          if (p[i + 1] < loy) loy = p[i + 1].toDouble();
          if (p[i + 1] > hiy) hiy = p[i + 1].toDouble();
          if (p[i + 2] < loz) loz = p[i + 2].toDouble();
          if (p[i + 2] > hiz) hiz = p[i + 2].toDouble();
        }
        return Bounds.ofBox(m * Mat4.scaling(n.sx, n.sy, n.sz), lox, hix, loy, hiy, loz, hiz);
      case GroupNode():
        Bounds? acc;
        for (final c in n.children) {
          final b = of(c, m);
          if (b != null) acc = acc == null ? b : acc.union(b);
        }
        return acc;
    }
  }

  /// Union of several nodes' bounds (null if none has any).
  static Bounds? ofAll(Iterable<SceneNode> nodes) {
    Bounds? acc;
    for (final n in nodes) {
      final b = of(n);
      if (b != null) acc = acc == null ? b : acc.union(b);
    }
    return acc;
  }
}
