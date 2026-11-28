import '../core/math/mat4.dart';
import '../domain/entities/document.dart';
import '../domain/entities/placement.dart';
import '../domain/entities/scene_node.dart';
import '../domain/ports/geometry_engine.dart';

/// One drawable piece of the evaluated scene. Mesh vertices are already in world space.
final class RenderItem {
  const RenderItem({required this.nodeId, required this.mesh, required this.isHole});
  final String nodeId;
  final MeshData mesh;
  final bool isHole;
}

final class EvaluationResult {
  const EvaluationResult(this.items, this.warnings);
  final List<RenderItem> items;

  /// Human-readable problems that did not stop evaluation (e.g. a boolean fell back to a bundle).
  final List<String> warnings;
}

/// Turns the design tree into world-space meshes using a [GeometryEngine].
///
/// Mirrors DabbleCAD's `solidBoolean`: a group unions (or intersects) its solid children and
/// subtracts its holes; if the kernel rejects an operand (not watertight) the group degrades to a
/// bundle so the user still sees every part. Results are cached by `geometryKey`, so editing one
/// shape only recomputes the groups that contain it.
final class SceneEvaluator {
  SceneEvaluator(this._engine);
  final GeometryEngine _engine;
  final Map<String, Future<List<_Part>>> _cache = {};
  final Set<String> _seen = {};
  final List<String> _warnings = [];

  /// Number of cache misses so far (exposed for tests and diagnostics).
  int computeCount = 0;

  Future<EvaluationResult> evaluate(Document doc) async {
    _seen.clear();
    _warnings.clear();
    final items = <RenderItem>[];
    for (final root in doc.roots) {
      // Mark the whole subtree: a cached group is not re-walked, but its descendants must survive pruning.
      _markSeen(root);
      for (final p in await _parts(root)) {
        items.add(RenderItem(nodeId: p.nodeId, mesh: p.mesh, isHole: p.isHole));
      }
    }
    _cache.removeWhere((k, _) => !_seen.contains(k));
    return EvaluationResult(items, List.unmodifiable(_warnings));
  }

  /// All solid parts (holes excluded) as one mesh, for export. Null when there is nothing solid.
  Future<MeshData?> combinedSolid(Document doc) async {
    final r = await evaluate(doc);
    final solids = [for (final i in r.items) if (!i.isHole) i.mesh];
    if (solids.isEmpty) return null;
    if (solids.length == 1) return solids.single;
    try {
      return await _engine.boolean(solids: solids, holes: const [], mode: BooleanMode.union);
    } on NotWatertightFailure {
      return null;
    }
  }

  static String _keyOf(SceneNode n) => '${n.id}#${n.geometryKey}';

  void _markSeen(SceneNode n) {
    _seen.add(_keyOf(n));
    if (n is GroupNode) {
      for (final c in n.children) {
        _markSeen(c);
      }
    }
  }

  Future<List<_Part>> _parts(SceneNode node) {
    // The id is part of the key: two identical shapes at the same place are still different nodes,
    // and each cached part is labelled with its owner's id (needed for selection and picking).
    return _cache.putIfAbsent(_keyOf(node), () {
      computeCount++;
      return _compute(node);
    });
  }

  Future<List<_Part>> _compute(SceneNode node) async {
    switch (node) {
      case ShapeNode():
        final raw = await _engine.primitive(node.kind, width: node.width, depth: node.depth, height: node.height);
        // Placement.z is the bottom of the shape: lift the centred primitive by half its height.
        final m = node.placement.toMatrix() * Mat4.translation(0, 0, node.height / 2);
        return [_Part(node.id, await _engine.transform(raw, m), node.isHole)];
      case OutlineNode():
        try {
          final meshes = [for (final sh in node.shapes) await _engine.extrude(sh.outlines, node.height)];
          final one = meshes.length == 1 ? meshes.single : await _engine.boolean(solids: meshes, holes: const [], mode: BooleanMode.union);
          // extrusion spans z = 0..height from the placement, so no lift is needed
          return [_Part(node.id, await _engine.transform(one, node.placement.toMatrix()), node.isHole)];
        } on EngineFailure catch (e) {
          _warnings.add('"${node.name}": ${e.message}. Skipped.');
          return const [];
        }
      case MeshNode():
        // the mesh rests on z = 0 (centred in X/Y); scaling about that origin keeps it on the workplane
        return [_Part(node.id, await _engine.transform(node.mesh, node.placement.toMatrix() * Mat4.scaling(node.sx, node.sy, node.sz)), node.isHole)];
      case GroupNode():
        final kids = <_Part>[];
        for (final c in node.children) {
          kids.addAll(await _parts(c));
        }
        final combined = node.op == GroupOp.bundle ? kids : await _combine(node, kids);
        if (node.placement == Placement.origin) return combined;
        final m = node.placement.toMatrix();
        return [for (final p in combined) _Part(p.nodeId, await _engine.transform(p.mesh, m), p.isHole)];
    }
  }

  Future<List<_Part>> _combine(GroupNode g, List<_Part> kids) async {
    final solids = [for (final k in kids) if (!k.isHole) k.mesh];
    final holes = [for (final k in kids) if (k.isHole) k.mesh];
    if (solids.isEmpty) return kids;
    if (solids.length == 1 && holes.isEmpty) return [_Part(g.id, solids.single, g.isHole)];
    try {
      final mode = g.op == GroupOp.intersect ? BooleanMode.intersect : BooleanMode.union;
      final out = await _engine.boolean(solids: solids, holes: holes, mode: mode);
      return [_Part(g.id, out, g.isHole)];
    } on EngineFailure catch (e) {
      _warnings.add('"${g.name}": ${e.message}. Showing parts separately.');
      return kids;
    }
  }
}

final class _Part {
  const _Part(this.nodeId, this.mesh, this.isHole);
  final String nodeId;
  final MeshData mesh;
  final bool isHole;
}
