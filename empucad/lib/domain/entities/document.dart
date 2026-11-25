import '../laser/laser_models.dart';
import 'scene_node.dart';

/// The whole design: an ordered forest of nodes. Immutable; edits return a new [Document].
final class Document {
  const Document({this.name = 'Untitled', this.roots = const [], this.laser = const LaserSetup()});
  final String name;
  final List<SceneNode> roots;
  final LaserSetup laser;

  Document copyWith({String? name, List<SceneNode>? roots, LaserSetup? laser}) =>
      Document(name: name ?? this.name, roots: roots ?? this.roots, laser: laser ?? this.laser);

  SceneNode? find(String id) => _find(roots, id);

  static SceneNode? _find(List<SceneNode> nodes, String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
      if (n is GroupNode) {
        final hit = _find(n.children, id);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// Every node, depth first.
  Iterable<SceneNode> get allNodes sync* {
    Iterable<SceneNode> walk(List<SceneNode> ns) sync* {
      for (final n in ns) {
        yield n;
        if (n is GroupNode) yield* walk(n.children);
      }
    }

    yield* walk(roots);
  }

  /// Applies [f] to the node with [id], wherever it is in the tree.
  Document updateNode(String id, SceneNode Function(SceneNode) f) => copyWith(roots: _map(roots, id, f));

  static List<SceneNode> _map(List<SceneNode> nodes, String id, SceneNode Function(SceneNode) f) => [
        for (final n in nodes)
          if (n.id == id)
            f(n)
          else if (n is GroupNode)
            n.copyWith(children: _map(n.children, id, f))
          else
            n,
      ];

  Document removeIds(Set<String> ids) {
    final next = copyWith(roots: _remove(roots, ids));
    // drop laser assignments of nodes that no longer exist
    final live = {for (final n in next.allNodes) n.id};
    final kept = {for (final e in laser.layerOf.entries) if (live.contains(e.key)) e.key: e.value};
    return kept.length == laser.layerOf.length ? next : next.copyWith(laser: laser.copyWith(layerOf: kept));
  }

  static List<SceneNode> _remove(List<SceneNode> nodes, Set<String> ids) => [
        for (final n in nodes)
          if (!ids.contains(n.id)) n is GroupNode ? n.copyWith(children: _remove(n.children, ids)) : n,
      ];
}
