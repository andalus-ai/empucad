import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/document_ops.dart';
import '../../application/history.dart';
import '../../domain/cnc/tool_library.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/placement.dart';
import '../../domain/entities/scene_node.dart';
import '../../domain/laser/laser_models.dart';

/// Immutable snapshot the UI watches.
final class EditorState {
  const EditorState({required this.document, required this.canUndo, required this.canRedo});
  final Document document;
  final bool canUndo, canRedo;
}

/// Owns the document history. Every edit is a pure [DocumentOps] call pushed onto [History].
class EditorNotifier extends Notifier<EditorState> {
  late History<Document> _history;
  int _seq = 0;

  @override
  EditorState build() {
    _history = History(const Document());
    return _snapshot();
  }

  EditorState _snapshot() => EditorState(document: _history.present, canUndo: _history.canUndo, canRedo: _history.canRedo);

  String _newId() => 'n${++_seq}';

  /// A fresh node id (for nodes built outside the notifier, e.g. SVG imports).
  String nextId() => _newId();

  void addNode(SceneNode node) => _commit(DocumentOps.add(_history.present, node));

  void _commit(Document d) {
    _history.push(d);
    state = _snapshot();
  }

  /// Adds a default-sized shape and returns its id so the caller can select it.
  String addShape(ShapeKind kind) {
    final id = _newId();
    final n = _history.present.roots.length;
    final at = Placement(x: 25.0 * (n % 5), y: 25.0 * (n ~/ 5));
    final label = '${kind.name[0].toUpperCase()}${kind.name.substring(1)} $id';
    final node = kind == ShapeKind.box
        ? ShapeNode(id: id, name: label, kind: kind, width: 20, depth: 20, height: 20, placement: at)
        : ShapeNode.round(id: id, name: label, kind: kind, diameter: 20, height: 20, placement: at);
    _commit(DocumentOps.add(_history.present, node));
    return id;
  }

  void delete(Set<String> ids) => _commit(DocumentOps.remove(_history.present, ids));
  void nudge(String id, {double dx = 0, double dy = 0, double dz = 0}) => _commit(DocumentOps.move(_history.present, id, dx: dx, dy: dy, dz: dz));
  void toggleHole(Set<String> ids) => _commit(DocumentOps.toggleHole(_history.present, ids));
  void recolor(Set<String> ids, int color) => _commit(DocumentOps.recolor(_history.present, ids, color));
  void setPlacement(String id, Placement p) => _commit(DocumentOps.setPlacement(_history.present, id, p));

  void resize(String id, {double? width, double? depth, double? height}) {
    final d = _history.present.updateNode(id, (n) {
      if (n is! ShapeNode) return n;
      // round shapes keep width == depth
      final round = n.kind != ShapeKind.box;
      final w = width ?? (round && depth != null ? depth : n.width);
      return n.copyWith(width: w, depth: round ? w : (depth ?? n.depth), height: height ?? n.height);
    });
    _commit(d);
  }

  void setOutlineHeight(String id, double height) =>
      _commit(_history.present.updateNode(id, (n) => n is OutlineNode ? n.copyWith(height: height) : n));

  void assignLaserLayer(Set<String> ids, int layer) => _commit(DocumentOps.assignLayer(_history.present, ids, layer));
  void updateLaserLayer(LaserLayerSettings l) => _commit(DocumentOps.updateLayer(_history.present, l));
  void updateTool(CncTool t) => _commit(DocumentOps.updateTool(_history.present, t));
  void removeTool(String id) => _commit(DocumentOps.removeTool(_history.present, id));

  /// Adds a copy of [from] (same speeds) under a fresh id and returns that id.
  String duplicateTool(CncTool from) {
    var n = _history.present.tools.tools.length + 1;
    while (_history.present.tools.find('t$n') != null) {
      n++;
    }
    final id = 't$n';
    _commit(DocumentOps.addTool(_history.present, CncTool(id: id, name: '${from.name} copy', kind: from.kind, diameter: from.diameter, feed: from.feed, plunge: from.plunge, rpm: from.rpm, angle: from.angle)));
    return id;
  }

  void setRaster(RasterAsset a) => _commit(DocumentOps.setRaster(_history.present, a));
  void updateRasterSettings(RasterSettings s) => _commit(DocumentOps.updateRasterSettings(_history.present, s));
  void clearRaster() => _commit(DocumentOps.clearRaster(_history.present));
  void setLaserMachine(LaserMachine m) => _commit(DocumentOps.setMachine(_history.present, m));

  /// Returns the new group's id, or null if nothing was grouped.
  String? group(Set<String> ids, {GroupOp op = GroupOp.union}) {
    final id = _newId();
    final next = DocumentOps.group(_history.present, ids, groupId: id, op: op);
    if (identical(next, _history.present)) return null;
    _commit(next);
    return id;
  }

  void ungroup(String groupId) => _commit(DocumentOps.ungroup(_history.present, groupId));

  void undo() {
    _history.undo();
    state = _snapshot();
  }

  void redo() {
    _history.redo();
    state = _snapshot();
  }

  /// Replace the whole design (open file). Starts a fresh history.
  void load(Document d) {
    _history = History(d);
    _seq = d.allNodes.length + 1000; // ids from the file stay unique against new ones
    state = _snapshot();
  }
}

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(EditorNotifier.new);

/// Just the document, so widgets that only need geometry don't rebuild on undo/redo flags.
final documentProvider = Provider<Document>((ref) => ref.watch(editorProvider.select((s) => s.document)));
