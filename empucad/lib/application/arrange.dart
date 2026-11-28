import 'dart:math' as math;

import '../core/math/mat4.dart';
import '../domain/entities/document.dart';
import '../domain/entities/placement.dart';
import '../domain/entities/scene_node.dart';
import 'node_bounds.dart';

enum AlignMode { left, centerX, right, front, centerY, back, base, top }

final class ArrangeResult {
  const ArrangeResult(this.document, this.newIds);
  final Document document;

  /// Ids of the copies that were created (empty for operations that create nothing).
  final List<String> newIds;
}

/// Duplicating, arraying and aligning top-level nodes. Pure functions on [Document]; `nextId` is supplied
/// by the caller so ids stay unique across the whole editor.
abstract final class Arrange {
  /// Deep copy of [n] with fresh ids for the node and every descendant. [idMap] receives old -> new.
  static SceneNode clone(SceneNode n, String Function() nextId, Map<String, String> idMap) {
    final id = nextId();
    idMap[n.id] = id;
    return switch (n) {
      ShapeNode() => ShapeNode(id: id, name: n.name, kind: n.kind, width: n.width, depth: n.depth, height: n.height, placement: n.placement, isHole: n.isHole, color: n.color),
      OutlineNode() => OutlineNode(id: id, name: n.name, shapes: n.shapes, height: n.height, placement: n.placement, isHole: n.isHole, color: n.color),
      MeshNode() => MeshNode(
          id: id, name: n.name, mesh: n.mesh, meshHash: n.meshHash, meshWidth: n.meshWidth, meshDepth: n.meshDepth, meshHeight: n.meshHeight,
          sx: n.sx, sy: n.sy, sz: n.sz, placement: n.placement, isHole: n.isHole, color: n.color),
      GroupNode() => GroupNode(id: id, name: n.name, op: n.op, placement: n.placement, isHole: n.isHole, color: n.color, children: [for (final c in n.children) clone(c, nextId, idMap)]),
    };
  }

  /// The selected top-level nodes, in document order. Nested ids are ignored.
  static List<SceneNode> _topLevel(Document d, Set<String> ids) => [for (final n in d.roots) if (ids.contains(n.id)) n];

  /// Copies of the selection, each moved by `transform(i)` (1-based copy number) applied to the node's
  /// world matrix. Copies are added after the originals; laser layer assignments are carried over.
  static ArrangeResult _copies(Document d, Set<String> ids, int count, String Function() nextId, Placement Function(SceneNode original, int i) place) {
    final sel = _topLevel(d, ids);
    if (sel.isEmpty || count < 1) return ArrangeResult(d, const []);
    final roots = [...d.roots];
    final created = <String>[];
    final layerOf = {...d.laser.layerOf};
    for (var i = 1; i <= count; i++) {
      for (final n in sel) {
        final map = <String, String>{};
        final c = clone(n, nextId, map).withPlacement(place(n, i));
        roots.add(c);
        created.add(c.id);
        for (final e in map.entries) {
          final layer = d.laser.layerOf[e.key];
          if (layer != null) layerOf[e.value] = layer;
        }
      }
    }
    final laser = layerOf.length == d.laser.layerOf.length ? d.laser : d.laser.copyWith(layerOf: layerOf);
    return ArrangeResult(d.copyWith(roots: roots, laser: laser), created);
  }

  /// `count` extra copies, each offset by another (dx, dy, dz): copy i sits at i * (dx, dy, dz).
  static ArrangeResult linear(Document d, Set<String> ids, {required int count, double dx = 0, double dy = 0, double dz = 0, required String Function() nextId}) =>
      _copies(d, ids, count, nextId, (n, i) => n.placement.copyWith(x: n.placement.x + dx * i, y: n.placement.y + dy * i, z: n.placement.z + dz * i));

  /// A grid of `rows` x `columns` including the original: the original is cell (0,0).
  static ArrangeResult grid(Document d, Set<String> ids, {required int rows, required int columns, required double dx, required double dy, required String Function() nextId}) {
    if (rows < 1 || columns < 1 || rows * columns < 2) return ArrangeResult(d, const []);
    final cells = <(int, int)>[for (var r = 0; r < rows; r++) for (var c = 0; c < columns; c++) if (r != 0 || c != 0) (r, c)];
    return _copies(d, ids, cells.length, nextId, (n, i) {
      final (r, c) = cells[i - 1];
      return n.placement.copyWith(x: n.placement.x + dx * c, y: n.placement.y + dy * r);
    });
  }

  /// `count` extra copies spread around (cx, cy). With `totalAngle` 360 the original plus copies are evenly
  /// spaced round the full circle; with less, copy i is at i * totalAngle / count (an arc).
  static ArrangeResult circular(Document d, Set<String> ids, {required int count, required double cx, required double cy, double totalAngle = 360, required String Function() nextId}) {
    final step = totalAngle >= 360 ? 360.0 / (count + 1) : totalAngle / count;
    return _copies(d, ids, count, nextId, (n, i) {
      final turn = Mat4.translation(cx, cy, 0) * Mat4.rotationZ(step * i) * Mat4.translation(-cx, -cy, 0);
      final w = (turn * n.placement.toMatrix()).decompose();
      return Placement(x: w.tx, y: w.ty, z: w.tz, rx: w.rxDeg, ry: w.ryDeg, rz: w.rzDeg);
    });
  }

  /// Moves the selected top-level nodes so their bounds line up with the selection's overall bounds.
  /// `front` is the low-Y edge and `back` the high-Y edge. Needs at least two nodes.
  static Document align(Document d, Set<String> ids, AlignMode mode) {
    final sel = _topLevel(d, ids);
    if (sel.length < 2) return d;
    final all = NodeBounds.ofAll(sel);
    if (all == null) return d;
    var out = d;
    for (final n in sel) {
      final b = NodeBounds.of(n);
      if (b == null) continue;
      final (dx, dy, dz) = switch (mode) {
        AlignMode.left => (all.minX - b.minX, 0.0, 0.0),
        AlignMode.right => (all.maxX - b.maxX, 0.0, 0.0),
        AlignMode.centerX => (all.centerX - b.centerX, 0.0, 0.0),
        AlignMode.front => (0.0, all.minY - b.minY, 0.0),
        AlignMode.back => (0.0, all.maxY - b.maxY, 0.0),
        AlignMode.centerY => (0.0, all.centerY - b.centerY, 0.0),
        AlignMode.base => (0.0, 0.0, all.minZ - b.minZ),
        AlignMode.top => (0.0, 0.0, all.maxZ - b.maxZ),
      };
      if (dx == 0 && dy == 0 && dz == 0) continue;
      out = out.updateNode(n.id, (x) => x.withPlacement(x.placement.copyWith(x: x.placement.x + dx, y: x.placement.y + dy, z: x.placement.z + dz)));
    }
    return out;
  }

  /// Convenience for the toolbar: one copy offset by (dx, dy).
  static ArrangeResult duplicate(Document d, Set<String> ids, {double dx = 10, double dy = 10, required String Function() nextId}) =>
      linear(d, ids, count: 1, dx: dx, dy: dy, nextId: nextId);

  /// Radius of the circle through a node's centre about a point; used to pre-fill circular arrays.
  static double distanceFrom(SceneNode n, double cx, double cy) {
    final b = NodeBounds.of(n);
    return b == null ? 0 : math.sqrt(math.pow(b.centerX - cx, 2) + math.pow(b.centerY - cy, 2));
  }
}
