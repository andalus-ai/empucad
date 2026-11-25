import 'dart:math' as math;

import '../core/math/mat4.dart';
import '../domain/entities/document.dart';
import '../domain/entities/scene_node.dart';
import '../domain/ports/cam_engine.dart';

/// Top-view outlines of the design's solid shapes, ready for CAM. Each shape becomes one
/// [ShapeOutlines] (the engine unions separate shapes). Hole nodes are skipped.
///
/// A footprint is the shape's base outline projected onto the XY plane, so it is exact for shapes
/// lying flat on the workplane and for any Z rotation.
abstract final class Footprint {
  static const _roundSegments = 64;

  static List<ShapeOutlines> of(Document doc, {Set<String>? only}) {
    final out = <ShapeOutlines>[];
    void walk(SceneNode n, Mat4 parent, bool selected) {
      if (n.isHole) return;
      final m = parent * n.placement.toMatrix();
      final sel = selected || only == null || only.contains(n.id);
      switch (n) {
        case ShapeNode():
          if (sel) out.add(ShapeOutlines([_outline(n, m)]));
        case OutlineNode():
          if (sel) {
            out.add(ShapeOutlines([
              for (final o in n.shapes.expand((s) => s.outlines))
                Outline([
                  for (var i = 0; i + 1 < o.points.length; i += 2) ...() {
                    final p = m.transformPoint(o.points[i], o.points[i + 1], 0);
                    return [p.x, p.y];
                  }(),
                ], closed: o.closed),
            ]));
          }
        case GroupNode():
          for (final c in n.children) {
            walk(c, m, sel);
          }
      }
    }

    for (final r in doc.roots) {
      walk(r, Mat4.identity, false);
    }
    return out;
  }

  static Outline _outline(ShapeNode s, Mat4 m) {
    final hw = s.width / 2, hd = s.depth / 2;
    final local = switch (s.kind) {
      ShapeKind.box => [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)],
      _ => [
          for (var i = 0; i < _roundSegments; i++)
            (hw * math.cos(2 * math.pi * i / _roundSegments), hd * math.sin(2 * math.pi * i / _roundSegments)),
        ],
    };
    final pts = <double>[];
    for (final (x, y) in local) {
      final p = m.transformPoint(x, y, 0);
      pts..add(p.x)..add(p.y);
    }
    return Outline(pts);
  }
}
