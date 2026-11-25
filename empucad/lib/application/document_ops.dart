import 'dart:math' as math;

import '../domain/entities/document.dart';
import '../domain/entities/placement.dart';
import '../domain/entities/scene_node.dart';
import '../domain/laser/laser_models.dart';

/// Pure document edits. Each returns a new [Document]; none touch state, UI or the engine.
/// The Riverpod notifier only decides *when* to call these.
abstract final class DocumentOps {
  static Document add(Document d, SceneNode n) => d.copyWith(roots: [...d.roots, n]);

  static Document remove(Document d, Set<String> ids) => d.removeIds(ids);

  static Document move(Document d, String id, {double dx = 0, double dy = 0, double dz = 0}) =>
      d.updateNode(id, (n) => n.withPlacement(n.placement.copyWith(x: n.placement.x + dx, y: n.placement.y + dy, z: n.placement.z + dz)));

  static Document setPlacement(Document d, String id, Placement p) => d.updateNode(id, (n) => n.withPlacement(p));

  static Document toggleHole(Document d, Set<String> ids) {
    var out = d;
    for (final id in ids) {
      out = out.updateNode(id, (n) => n.withHole(!n.isHole));
    }
    return out;
  }

  static Document recolor(Document d, Set<String> ids, int color) {
    var out = d;
    for (final id in ids) {
      out = out.updateNode(id, (n) => n.withColor(color));
    }
    return out;
  }

  /// Groups top-level nodes in [ids] into one [GroupNode] placed where the first one was.
  /// Returns the document unchanged when fewer than two top-level nodes are selected.
  static Document group(Document d, Set<String> ids, {required String groupId, GroupOp op = GroupOp.union}) {
    final picked = d.roots.where((n) => ids.contains(n.id)).toList();
    if (picked.length < 2) return d;
    final at = d.roots.indexWhere((n) => ids.contains(n.id));
    final g = GroupNode(id: groupId, name: 'Group', children: picked, op: op);
    final rest = d.roots.where((n) => !ids.contains(n.id)).toList();
    final insertAt = rest.length < at ? rest.length : at;
    return d.copyWith(roots: [...rest.sublist(0, insertAt), g, ...rest.sublist(insertAt)]);
  }

  /// Replaces a top-level group by its children, baking the group's placement into each child.
  /// Supports groups rotated about Z only; a group tilted about X or Y is left unchanged
  /// because its children's rotations cannot be expressed in the simple placement model.
  static Document ungroup(Document d, String groupId) {
    final i = d.roots.indexWhere((n) => n.id == groupId);
    if (i < 0) return d;
    final g = d.roots[i];
    if (g is! GroupNode || g.placement.rx != 0 || g.placement.ry != 0) return d;
    final r = g.placement.rz * math.pi / 180;
    final (s, c) = (math.sin(r), math.cos(r));
    final kids = [
      for (final k in g.children)
        k.withPlacement(k.placement.copyWith(
          x: g.placement.x + k.placement.x * c - k.placement.y * s,
          y: g.placement.y + k.placement.x * s + k.placement.y * c,
          z: g.placement.z + k.placement.z,
          rz: k.placement.rz + g.placement.rz,
        )),
    ];
    return d.copyWith(roots: [...d.roots.sublist(0, i), ...kids, ...d.roots.sublist(i + 1)]);
  }

  /// Burn these nodes on laser layer [layer]. Unknown layers are ignored.
  static Document assignLayer(Document d, Set<String> ids, int layer) {
    if (d.laser.layer(layer) == null || ids.isEmpty) return d;
    final map = {...d.laser.layerOf, for (final id in ids) id: layer};
    return d.copyWith(laser: d.laser.copyWith(layerOf: map));
  }

  static Document updateLayer(Document d, LaserLayerSettings updated) => d.copyWith(
        laser: d.laser.copyWith(layers: [for (final l in d.laser.layers) l.index == updated.index ? updated : l]),
      );

  static Document setMachine(Document d, LaserMachine m) => d.copyWith(laser: d.laser.copyWith(machine: m));
}
