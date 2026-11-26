import 'dart:convert';
import 'dart:math' as math;

import '../../core/math/mat4.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/placement.dart';
import '../../domain/entities/scene_node.dart';
import '../../domain/laser/laser_models.dart';

final class DabbleImport {
  const DabbleImport(this.document, this.warnings);
  final Document document;

  /// Everything that could not be carried across exactly, in plain language.
  final List<String> warnings;
}

/// Reads a DabbleCAD design file (`.dabble`, JSON with `"app": "DabbleCAD"`).
///
/// Imported: box, cylinder, sphere and cone shapes, groups (union / intersect / bundle), holes, names,
/// colours, and each node's position, rotation and size; plus the settings of laser layers 1 to 5.
/// Everything else is skipped or simplified and reported in [DabbleImport.warnings], never silently.
///
/// DabbleCAD stores size as a scale inside each node's matrix, with every shape built centred in X and Y
/// and resting on z = 0, nominally 20 mm. EmpuCAD stores size and placement separately, so each matrix is
/// split with [Mat4.decompose]. A group's scale cannot live on an EmpuCAD group, so it is pushed down
/// into its children.
abstract final class DabbleImporter {
  static const app = 'DabbleCAD';
  static const _nominal = 20.0;
  static const _maxDepth = 64;

  static bool looksLike(Object? json) => json is Map<String, dynamic> && json['app'] == app;

  static DabbleImport fromText(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('Not valid JSON: ${e.message}');
    }
    if (!looksLike(json)) throw const FormatException('Not a DabbleCAD design file');
    return fromJson(json as Map<String, dynamic>);
  }

  static DabbleImport fromJson(Map<String, dynamic> json) {
    final nodes = json['nodes'];
    if (nodes is! List) throw const FormatException('The DabbleCAD file has no "nodes" list');
    final ctx = _Ctx();
    final roots = <SceneNode>[];
    for (final n in nodes) {
      final c = _node(n, Mat4.identity, ctx, 0);
      if (c != null) roots.add(c);
    }
    final laser = _laser(json['laser'], ctx);
    final name = json['name'];
    return DabbleImport(
      Document(name: name is String && name.trim().isNotEmpty ? name.trim() : 'Imported design', roots: roots, laser: laser),
      ctx.warnings(),
    );
  }

  static SceneNode? _node(Object? raw, Mat4 pre, _Ctx c, int depth) {
    if (depth > _maxDepth) throw const FormatException('Groups are nested too deeply');
    if (raw is! Map<String, dynamic>) throw const FormatException('A node must be an object');
    if (raw['hidden'] == true) {
      c.hidden++;
      return null;
    }
    final world = pre * _matrix(raw["matrix"]);
    final d = world.decompose();
    final placement = Placement(x: d.tx, y: d.ty, z: d.tz, rx: d.rxDeg, ry: d.ryDeg, rz: d.rzDeg);
    final hole = raw['hole'] == true;
    final color = _color(raw['color']);
    final name = raw['name'] is String && (raw['name'] as String).trim().isNotEmpty ? (raw['name'] as String).trim() : null;

    switch (raw['type']) {
      case 'group':
        if (d.sheared) c.sheared++;
        if (d.mirrored) c.mirroredGroups++;
        final kids = raw['children'];
        if (kids is! List) throw const FormatException('A group has no "children" list');
        // the group keeps translation + rotation; its scale is applied to the children instead
        final scaleOnly = Mat4.scaling(d.sx, d.sy, d.sz);
        final converted = <SceneNode>[];
        for (final k in kids) {
          final n = _node(k, scaleOnly, c, depth + 1);
          if (n != null) converted.add(n);
        }
        if (converted.isEmpty) {
          c.emptyGroups++;
          return null;
        }
        final mode = raw['mode'];
        return GroupNode(
          id: c.newId(),
          name: name ?? 'Group',
          children: converted,
          op: mode == 'intersect' ? GroupOp.intersect : (mode == 'bundle' ? GroupOp.bundle : GroupOp.union),
          placement: placement,
          isHole: hole,
          color: color,
        );
      case 'shape':
        if (d.sheared) c.sheared++;
        return _shape(raw, d, placement, name, hole, color, c);
      default:
        c.skip('${raw['type']}');
        return null;
    }
  }

  static ShapeNode? _shape(Map<String, dynamic> raw, Decomposed d, Placement p, String? name, bool hole, int color, _Ctx c) {
    final kind = raw['kind'];
    final params = raw['params'] is Map<String, dynamic> ? raw['params'] as Map<String, dynamic> : const <String, dynamic>{};
    double param(String k, double dflt) => params[k] is num && (params[k] as num).isFinite ? (params[k] as num).toDouble() : dflt;
    bool same(double a, double b) => (a - b).abs() <= 0.01 * math.max(a, b).clamp(1e-9, double.infinity);
    final height = _nominal * d.sz;

    switch (kind) {
      case 'box':
        if (param('radius', 0) > 0.01) c.rounded++;
        return ShapeNode(id: c.newId(), name: name ?? 'Box', kind: ShapeKind.box, width: _nominal * d.sx, depth: _nominal * d.sy, height: height, placement: p, isHole: hole, color: color);
      case 'cylinder':
        if (param('bevel', 0) > 0.01) c.rounded++;
        if (param('sides', 48) < 24) c.fewSides++;
        if (!same(d.sx, d.sy)) c.elliptical++;
        return ShapeNode.round(id: c.newId(), name: name ?? 'Cylinder', kind: ShapeKind.cylinder, diameter: _nominal * (d.sx + d.sy) / 2, height: height, placement: p, isHole: hole, color: color);
      case 'sphere':
        if (!same(d.sx, d.sy) || !same(d.sx, d.sz)) c.ellipsoid++;
        return ShapeNode.round(id: c.newId(), name: name ?? 'Sphere', kind: ShapeKind.sphere, diameter: _nominal * (d.sx + d.sy) / 2, height: _nominal * (d.sx + d.sy) / 2, placement: p, isHole: hole, color: color);
      case 'cone':
        if (param('top', 0) > 0.01) c.frustum++;
        if (!same(d.sx, d.sy)) c.elliptical++;
        return ShapeNode.round(id: c.newId(), name: name ?? 'Cone', kind: ShapeKind.cone, diameter: 2 * param('base', 10) * (d.sx + d.sy) / 2, height: height, placement: p, isHole: hole, color: color);
      default:
        c.skip('$kind');
        return null;
    }
  }

  static Mat4 _matrix(Object? raw) {
    if (raw == null) return Mat4.identity;
    if (raw is! List || raw.length != 16 || raw.any((e) => e is! num || !e.isFinite)) {
      throw const FormatException('A node has an invalid transform matrix');
    }
    return Mat4.fromColumnMajor([for (final e in raw) (e as num).toDouble()]);
  }

  static int _color(Object? raw) {
    const fallback = 0xFF3B82F6;
    if (raw is! String || !raw.startsWith('#')) return fallback;
    var hex = raw.substring(1);
    if (hex.length == 3) hex = hex.split('').map((ch) => ch + ch).join();
    if (hex.length != 6) return fallback;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? fallback : 0xFF000000 | v;
  }

  /// DabbleCAD has up to 30 laser layers; EmpuCAD has 5, so only layers 1 to 5 are taken.
  static LaserSetup _laser(Object? raw, _Ctx c) {
    const base = LaserSetup();
    if (raw is! Map<String, dynamic>) return base;
    final shapes = raw['shapes'];
    if (shapes is List) c.laserShapes = shapes.length;
    final layers = raw['layers'];
    if (layers is! Map<String, dynamic>) return base;
    c.laserLayersBeyondFive = layers.keys.where((k) => (int.tryParse(k) ?? -1) >= base.layers.length).length;
    double? num_(Object? v, {double min = 0, double? max, bool exclusiveMin = false}) {
      if (v is! num || !v.isFinite) return null;
      final x = v.toDouble();
      if (exclusiveMin ? x <= min : x < min) return null;
      return max != null && x > max ? max : x;
    }

    final out = <LaserLayerSettings>[];
    for (final l in base.layers) {
      final r = layers['${l.index}'];
      if (r is! Map<String, dynamic>) {
        out.add(l);
        continue;
      }
      if (r['mode'] == 'image') c.imageLayers++;
      final passes = r['passes'];
      out.add(l.copyWith(
        mode: r['mode'] == 'fill' ? LaserLayerMode.fill : LaserLayerMode.line,
        speed: num_(r['speed'], exclusiveMin: true) ?? l.speed,
        power: num_(r['powerMax'], max: 100) ?? l.power,
        passes: passes is int && passes >= 1 ? passes : l.passes,
        interval: num_(r['interval'], exclusiveMin: true) ?? l.interval,
        angle: r['angle'] is num && (r['angle'] as num).isFinite ? (r['angle'] as num).toDouble() : l.angle,
        bidirectional: r['bidirectional'] != false,
        overscan: num_(r['overscan']) ?? l.overscan,
      ));
    }
    return base.copyWith(layers: out);
  }
}

class _Ctx {
  int _id = 0;
  String newId() => 'i${++_id}';

  final Map<String, int> skipped = {};
  int hidden = 0, rounded = 0, fewSides = 0, elliptical = 0, ellipsoid = 0, frustum = 0, sheared = 0, mirroredGroups = 0, emptyGroups = 0;
  int laserShapes = 0, laserLayersBeyondFive = 0, imageLayers = 0;

  void skip(String kind) => skipped[kind] = (skipped[kind] ?? 0) + 1;

  List<String> warnings() {
    String s(int n, String one, String many) => n == 1 ? one : many;
    final w = <String>[];
    if (skipped.isNotEmpty) {
      final total = skipped.values.fold<int>(0, (a, b) => a + b);
      final list = (skipped.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} x${e.value}').join(', ');
      w.add('Skipped $total ${s(total, 'shape', 'shapes')} EmpuCAD does not support yet: $list.');
    }
    if (hidden > 0) w.add('Skipped $hidden hidden ${s(hidden, 'shape', 'shapes')}.');
    if (emptyGroups > 0) w.add('Dropped $emptyGroups ${s(emptyGroups, 'group', 'groups')} with nothing left in ${s(emptyGroups, 'it', 'them')}.');
    if (rounded > 0) w.add('Rounded corners or bevels were dropped from $rounded ${s(rounded, 'shape', 'shapes')}.');
    if (fewSides > 0) w.add('$fewSides ${s(fewSides, 'cylinder', 'cylinders')} with few sides (such as hexagonal prisms) became round.');
    if (elliptical > 0) w.add('$elliptical round ${s(elliptical, 'shape was', 'shapes were')} stretched unevenly and made circular.');
    if (ellipsoid > 0) w.add('$ellipsoid ${s(ellipsoid, 'sphere was', 'spheres were')} squashed or stretched and made spherical.');
    if (frustum > 0) w.add('$frustum ${s(frustum, 'cone', 'cones')} with a flat top became pointed.');
    if (sheared > 0) w.add('$sheared ${s(sheared, 'item was', 'items were')} skewed by scaling a rotated group; size or angle may differ slightly.');
    if (mirroredGroups > 0) w.add('$mirroredGroups mirrored ${s(mirroredGroups, 'group', 'groups')} may come out flipped.');
    final laser = <String>[
      if (laserShapes > 0) '$laserShapes laser ${s(laserShapes, 'shape', 'shapes')}',
      if (imageLayers > 0) 'image-mode layer settings',
      if (laserLayersBeyondFive > 0) 'laser layers 6 and up',
    ];
    if (laser.isNotEmpty) w.add('Laser layer settings for layers 1 to 5 were imported, but not: ${laser.join(', ')}.');
    return w;
  }
}
