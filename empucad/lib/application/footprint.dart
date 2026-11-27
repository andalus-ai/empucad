import 'dart:math' as math;

import '../core/math/mat4.dart';
import '../domain/entities/document.dart';
import '../domain/entities/scene_node.dart';
import '../domain/ports/cam_engine.dart';

/// One design shape's top-view outlines plus the ids it came from: the leaf node first, then each
/// ancestor group. Callers (e.g. laser layers) use the ids to resolve inherited settings.
final class FootprintEntry {
  const FootprintEntry(this.ids, this.shape);
  final List<String> ids;
  final ShapeOutlines shape;
}

/// Top-view outlines of the design's solid shapes, ready for CAM and laser. Each shape becomes one
/// [ShapeOutlines] (the engines union separate shapes). Hole nodes are skipped.
///
/// A footprint is the shape's base outline projected onto the XY plane, so it is exact for shapes
/// lying flat on the workplane and for any Z rotation.
abstract final class Footprint {
  static const _roundSegments = 64;

  static List<ShapeOutlines> of(Document doc, {Set<String>? only}) => [for (final e in entries(doc, only: only)) e.shape];

  static List<FootprintEntry> entries(Document doc, {Set<String>? only}) {
    final out = <FootprintEntry>[];
    void walk(SceneNode n, Mat4 parent, bool selected, List<String> ancestors) {
      if (n.isHole) return;
      final m = parent * n.placement.toMatrix();
      final sel = selected || only == null || only.contains(n.id);
      switch (n) {
        case ShapeNode():
          if (sel) out.add(FootprintEntry([n.id, ...ancestors], ShapeOutlines([_outline(n, m)])));
        case OutlineNode():
          if (sel) {
            out.add(FootprintEntry([
              n.id,
              ...ancestors
            ], ShapeOutlines([
              for (final o in n.shapes.expand((s) => s.outlines))
                Outline([
                  for (var i = 0; i + 1 < o.points.length; i += 2) ..._xy(m, o.points[i], o.points[i + 1]),
                ], closed: o.closed),
            ])));
          }
        case GroupNode():
          for (final c in n.children) {
            walk(c, m, sel, [n.id, ...ancestors]);
          }
      }
    }

    for (final r in doc.roots) {
      walk(r, Mat4.identity, false, const []);
    }
    return out;
  }

  static List<double> _xy(Mat4 m, double x, double y) {
    final p = m.transformPoint(x, y, 0);
    return [p.x, p.y];
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
      pts.addAll(_xy(m, x, y));
    }
    return Outline(pts);
  }
}
