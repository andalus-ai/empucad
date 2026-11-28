import '../domain/entities/document.dart';
import '../domain/entities/outline.dart';
import '../domain/laser/laser_models.dart';
import 'footprint.dart';

final class LaserPlan {
  const LaserPlan({required this.shapes, required this.layers, required this.machine, required this.warnings});
  final List<LaserShapeInput> shapes;

  /// Only the enabled layers that have at least one shape.
  final List<LaserLayerSettings> layers;
  final LaserMachine machine;
  final List<String> warnings;
  bool get isEmpty => shapes.isEmpty;
}

/// Turns the design into laser input: resolves each shape's layer (own assignment, else the nearest
/// group's, else layer 0), drops disabled layers, and warns about shapes that leave the bed.
/// Output is in machine coordinates (origin bottom-left, Y up), the same space as the design, so
/// nothing is converted here. The engine adapter keeps that contract: Y in is Y out.
abstract final class LaserJobBuilder {
  static LaserPlan build(Document doc, {Set<String>? only}) {
    final setup = doc.laser;
    final shapes = <LaserShapeInput>[];
    var outside = 0;
    for (final e in Footprint.entries(doc, only: only)) {
      final layerIdx = _layerFor(e.ids, setup);
      final layer = setup.layer(layerIdx);
      if (layer == null || !layer.enabled) continue;
      final outlines = e.shape.outlines;
      if (_leavesBed(outlines, setup.machine)) outside++;
      shapes.add(LaserShapeInput(layer: layerIdx, outlines: outlines));
    }
    final used = {for (final s in shapes) s.layer};
    return LaserPlan(
      shapes: shapes,
      layers: [for (final l in setup.layers) if (l.enabled && used.contains(l.index)) l],
      machine: setup.machine,
      warnings: [if (outside > 0) '$outside shape${outside == 1 ? '' : 's'} extend${outside == 1 ? 's' : ''} outside the ${_mm(setup.machine.bedWidth)} x ${_mm(setup.machine.bedHeight)} mm bed.'],
    );
  }

  /// The laser layer a node burns on: its own assignment, else its nearest group's, else layer 0.
  /// Returns null when [nodeId] is not in the document.
  static int? layerOfNode(Document doc, String nodeId) {
    final path = doc.idPathTo(nodeId);
    return path.isEmpty ? null : _layerFor(path, doc.laser);
  }

  /// Colour to draw a node with while looking at laser layers: its layer's swatch, faded when that
  /// layer is switched off. Null when the node does not exist.
  static int? viewColor(Document doc, String nodeId) {
    final idx = layerOfNode(doc, nodeId);
    if (idx == null) return null;
    final layer = doc.laser.layer(idx);
    if (layer == null) return null;
    return layer.enabled ? layer.color : (layer.color & 0x00FFFFFF) | 0x55000000;
  }

  static int _layerFor(List<String> ids, LaserSetup setup) {
    for (final id in ids) {
      final l = setup.layerOf[id];
      if (l != null) return l;
    }
    return 0;
  }

  static bool _leavesBed(List<Outline> outlines, LaserMachine m) {
    const eps = 1e-6;
    for (final o in outlines) {
      for (var i = 0; i + 1 < o.points.length; i += 2) {
        final x = o.points[i], y = o.points[i + 1];
        if (x < -eps || y < -eps || x > m.bedWidth + eps || y > m.bedHeight + eps) return true;
      }
    }
    return false;
  }

  static String _mm(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
