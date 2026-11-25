import 'dart:convert';

import '../../domain/entities/document.dart';
import '../../domain/entities/outline.dart';
import '../../domain/entities/placement.dart';
import '../../domain/entities/scene_node.dart';
import '../../domain/laser/laser_models.dart';

/// Versioned JSON for `.empucad` files. Decoding validates strictly and throws [FormatException]
/// with a readable message, so a corrupt file never yields a half-built document.
abstract final class DocumentCodec {
  static const app = 'EmpuCAD';
  static const version = 1;

  static String encode(Document d) => const JsonEncoder.withIndent('  ').convert({
        'app': app,
        'version': version,
        'name': d.name,
        'nodes': [for (final n in d.roots) _node(n)],
        'laser': _laser(d.laser),
      });

  static Document decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic> || json['app'] != app) {
      throw const FormatException('Not an EmpuCAD file');
    }
    final v = json['version'];
    if (v is! int || v > version) {
      throw FormatException('Unsupported file version $v (this build reads up to $version)');
    }
    final nodes = json['nodes'];
    if (nodes is! List) throw const FormatException('Missing "nodes" list');
    return Document(
      name: (json['name'] as String?) ?? 'Untitled',
      roots: [for (final n in nodes) _decodeNode(n, 0)],
      laser: json['laser'] == null ? const LaserSetup() : _decodeLaser(json['laser']),
    );
  }

  static Map<String, Object?> _laser(LaserSetup l) => {
        'machine': {'bedW': l.machine.bedWidth, 'bedH': l.machine.bedHeight, 'sMax': l.machine.sMax, 'rapid': l.machine.rapid, 'dynamic': l.machine.dynamicPower},
        'layers': [
          for (final x in l.layers)
            {
              'index': x.index, 'name': x.name, 'color': x.color, 'mode': x.mode.name, 'speed': x.speed, 'power': x.power,
              'passes': x.passes, 'interval': x.interval, 'angle': x.angle, 'bidir': x.bidirectional, 'overscan': x.overscan, 'enabled': x.enabled,
            },
        ],
        'assign': l.layerOf,
      };

  static LaserSetup _decodeLaser(Object? raw) {
    if (raw is! Map<String, dynamic>) throw const FormatException('"laser" must be an object');
    double pos(Map<String, dynamic> m, String k, {bool allowZero = false}) {
      final v = m[k];
      if (v is! num || !v.isFinite || v < 0 || (!allowZero && v == 0)) throw FormatException('laser "$k" must be a positive number');
      return v.toDouble();
    }

    final mm = raw['machine'];
    if (mm is! Map<String, dynamic>) throw const FormatException('laser "machine" missing');
    final machine = LaserMachine(
      bedWidth: pos(mm, 'bedW'), bedHeight: pos(mm, 'bedH'), sMax: pos(mm, 'sMax'), rapid: pos(mm, 'rapid'), dynamicPower: mm['dynamic'] != false,
    );
    final rawLayers = raw['layers'];
    if (rawLayers is! List || rawLayers.isEmpty) throw const FormatException('laser "layers" must be a non-empty list');
    final layers = <LaserLayerSettings>[];
    for (final l in rawLayers) {
      if (l is! Map<String, dynamic>) throw const FormatException('laser layer must be an object');
      final idx = l['index'];
      if (idx is! int || idx < 0 || layers.any((x) => x.index == idx)) throw const FormatException('laser layer index must be unique and >= 0');
      final power = pos(l, 'power', allowZero: true);
      if (power > 100) throw const FormatException('laser power is a percentage (0-100)');
      final passes = l['passes'];
      if (passes is! int || passes < 1) throw const FormatException('laser "passes" must be an integer >= 1');
      layers.add(LaserLayerSettings(
        index: idx,
        name: l['name'] is String ? l['name'] as String : 'Layer $idx',
        color: l['color'] is int ? l['color'] as int : 0xFF9CA3AF,
        mode: LaserLayerMode.values.where((m) => m.name == l['mode']).firstOrNull ?? LaserLayerMode.line,
        speed: pos(l, 'speed'),
        power: power,
        passes: passes,
        interval: pos(l, 'interval'),
        angle: (l['angle'] is num && (l['angle'] as num).isFinite) ? (l['angle'] as num).toDouble() : 0,
        bidirectional: l['bidir'] != false,
        overscan: pos(l, 'overscan', allowZero: true),
        enabled: l['enabled'] != false,
      ));
    }
    final assign = raw['assign'];
    final layerOf = <String, int>{};
    if (assign is Map<String, dynamic>) {
      for (final e in assign.entries) {
        final v = e.value;
        if (v is! int || !layers.any((x) => x.index == v)) throw FormatException('"${e.key}" is assigned to an unknown laser layer');
        layerOf[e.key] = v;
      }
    } else if (assign != null) {
      throw const FormatException('laser "assign" must be an object');
    }
    return LaserSetup(machine: machine, layers: layers, layerOf: layerOf);
  }

  static Map<String, Object?> _node(SceneNode n) {
    final base = <String, Object?>{
      'id': n.id,
      'name': n.name,
      'hole': n.isHole,
      'color': n.color,
      'at': [n.placement.x, n.placement.y, n.placement.z],
      'rot': [n.placement.rx, n.placement.ry, n.placement.rz],
    };
    return switch (n) {
      ShapeNode() => {'type': 'shape', 'kind': n.kind.name, 'size': [n.width, n.depth, n.height], ...base},
      OutlineNode() => {
          'type': 'outline',
          'height': n.height,
          'shapes': [
            for (final sh in n.shapes)
              [
                for (final o in sh.outlines) {'closed': o.closed, 'pts': o.points},
              ],
          ],
          ...base,
        },
      GroupNode() => {'type': 'group', 'op': n.op.name, 'children': [for (final c in n.children) _node(c)], ...base},
    };
  }

  static SceneNode _decodeNode(Object? raw, int depth) {
    if (depth > 64) throw const FormatException('Groups nested too deeply');
    if (raw is! Map<String, dynamic>) throw const FormatException('Node must be an object');
    final id = _str(raw, 'id');
    final at = _nums(raw, 'at', 3), rot = _nums(raw, 'rot', 3);
    final placement = Placement(x: at[0], y: at[1], z: at[2], rx: rot[0], ry: rot[1], rz: rot[2]);
    final name = raw['name'] is String ? raw['name'] as String : id;
    final hole = raw['hole'] == true;
    final color = raw['color'] is int ? raw['color'] as int : 0xFF3B82F6;
    switch (raw['type']) {
      case 'shape':
        final kind = ShapeKind.values.where((k) => k.name == raw['kind']).firstOrNull;
        if (kind == null) throw FormatException('Unknown shape kind "${raw['kind']}" in $id');
        final s = _nums(raw, 'size', 3);
        if (s.any((v) => v <= 0)) throw FormatException('Shape $id has a non-positive size');
        return ShapeNode(id: id, name: name, kind: kind, width: s[0], depth: s[1], height: s[2], placement: placement, isHole: hole, color: color);
      case 'outline':
        final h = raw['height'];
        if (h is! num || !h.isFinite || h <= 0) throw FormatException('Outline $id has an invalid height');
        final rawShapes = raw['shapes'];
        if (rawShapes is! List) throw FormatException('Outline $id has no shapes');
        final shapes = <ShapeOutlines>[];
        for (final sh in rawShapes) {
          if (sh is! List) throw FormatException('Outline $id: a shape must be a list of outlines');
          final outlines = <Outline>[];
          for (final o in sh) {
            if (o is! Map<String, dynamic>) throw FormatException('Outline $id: bad outline');
            final pts = o['pts'];
            if (pts is! List || pts.length.isOdd || pts.any((e) => e is! num || !e.isFinite)) {
              throw FormatException('Outline $id: points must be finite x,y pairs');
            }
            outlines.add(Outline([for (final e in pts) (e as num).toDouble()], closed: o['closed'] != false));
          }
          shapes.add(ShapeOutlines(outlines));
        }
        return OutlineNode(id: id, name: name, shapes: shapes, height: h.toDouble(), placement: placement, isHole: hole, color: color);
      case 'group':
        final op = GroupOp.values.where((o) => o.name == raw['op']).firstOrNull ?? GroupOp.union;
        final kids = raw['children'];
        if (kids is! List) throw FormatException('Group $id has no children list');
        return GroupNode(id: id, name: name, op: op, children: [for (final k in kids) _decodeNode(k, depth + 1)], placement: placement, isHole: hole, color: color);
      default:
        throw FormatException('Unknown node type "${raw['type']}"');
    }
  }

  static String _str(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is! String || v.isEmpty) throw FormatException('Missing "$k"');
    return v;
  }

  static List<double> _nums(Map<String, dynamic> m, String k, int n) {
    final v = m[k];
    if (v is! List || v.length != n || v.any((e) => e is! num || !e.isFinite)) {
      throw FormatException('"$k" must be $n finite numbers');
    }
    return [for (final e in v) (e as num).toDouble()];
  }
}
