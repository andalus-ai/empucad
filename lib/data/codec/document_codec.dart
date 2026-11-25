import 'dart:convert';

import '../../domain/entities/document.dart';
import '../../domain/entities/placement.dart';
import '../../domain/entities/scene_node.dart';

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
    return Document(name: (json['name'] as String?) ?? 'Untitled', roots: [for (final n in nodes) _decodeNode(n, 0)]);
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
