import 'dart:convert';
import 'dart:math' as math;

import 'package:empucad/application/open_document.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/core/math/mat4.dart';
import 'package:empucad/data/import/dabble_importer.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/laser/laser_models.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

Mat4 xf(double tx, double ty, double tz, {double rx = 0, double ry = 0, double rz = 0, double sx = 1, double sy = 1, double sz = 1}) =>
    Mat4.translation(tx, ty, tz) * Mat4.rotationZ(rz) * Mat4.rotationY(ry) * Mat4.rotationX(rx) * Mat4.scaling(sx, sy, sz);

Map<String, Object?> shape(String kind, Mat4 m, {Map<String, Object?>? params, String color = '#ff8800', bool hole = false, bool hidden = false, String name = ''}) => {
      'id': 'x${m.hashCode}$kind', 'type': 'shape', 'kind': kind, 'name': name, 'params': params ?? {}, 'color': color,
      'hole': hole, 'transparent': false, 'locked': false, 'hidden': hidden, 'matrix': m.m,
    };

Map<String, Object?> grp(List<Map<String, Object?>> kids, Mat4 m, {String mode = 'union', bool hole = false}) =>
    {'id': 'g${kids.length}', 'type': 'group', 'mode': mode, 'name': '', 'color': '#888888', 'hole': hole, 'hidden': false, 'matrix': m.m, 'children': kids};

DabbleImport load(List<Map<String, Object?>> nodes, {Map<String, Object?>? laser, String name = 'Bracket'}) =>
    DabbleImporter.fromText(jsonEncode({'app': 'DabbleCAD', 'version': 1, 'name': name, 'nodes': nodes, 'laser': laser}));

List<(double, double, double)> sorted(Iterable<(double, double, double)> pts) {
  final l = pts.map((p) => (((p.$1 * 1e5).round()) / 1e5, ((p.$2 * 1e5).round()) / 1e5, ((p.$3 * 1e5).round()) / 1e5)).toList();
  l.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3)));
  return l;
}

/// World-space corners of a 20 mm DabbleCAD box under [world].
List<(double, double, double)> dabbleCorners(Mat4 world) => [
      for (final x in [-10.0, 10.0]) for (final y in [-10.0, 10.0]) for (final z in [0.0, 20.0]) () {
        final p = world.transformPoint(x, y, z);
        return (p.x, p.y, p.z);
      }(),
    ];

/// World-space corners of an imported box, walking the placements of every ancestor group.
List<(double, double, double)> empuCorners(ShapeNode s, List<GroupNode> ancestors) {
  var world = Mat4.identity;
  for (final g in ancestors) {
    world = world * g.placement.toMatrix();
  }
  world = world * s.placement.toMatrix();
  return [
    for (final x in [-s.width / 2, s.width / 2]) for (final y in [-s.depth / 2, s.depth / 2]) for (final z in [0.0, s.height]) () {
      final p = world.transformPoint(x, y, z);
      return (p.x, p.y, p.z);
    }(),
  ];
}

void main() {
  group('shapes', () {
    test('a default box imports as 20 x 20 x 20 at the origin, with its colour, name and hole flag', () {
      final r = load([shape('box', Mat4.identity, color: '#3b82f6', name: 'Base')]);
      final s = r.document.roots.single as ShapeNode;
      expect([s.kind, s.width, s.depth, s.height], [ShapeKind.box, 20, 20, 20]);
      expect([s.placement.x, s.placement.y, s.placement.z], [0, 0, 0]);
      expect(s.color, 0xFF3B82F6);
      expect(s.name, 'Base');
      expect(s.isHole, isFalse);
      expect(r.document.name, 'Bracket');
      expect(r.warnings, isEmpty);
    });

    test('scale becomes size: a 5 x 5 x 30 cylinder-ish stretch and a flattened box', () {
      final cyl = load([shape('cylinder', xf(10, 20, 5, sx: 0.5, sy: 0.5, sz: 1.5))]).document.roots.single as ShapeNode;
      expect([cyl.kind, cyl.width, cyl.depth, cyl.height], [ShapeKind.cylinder, 10, 10, 30]);
      expect([cyl.placement.x, cyl.placement.y, cyl.placement.z], [10, 20, 5]);
      final box = load([shape('box', xf(0, 0, 0, sx: 2.6, sy: 1, sz: 0.15))]).document.roots.single as ShapeNode;
      expect([box.width, box.depth].map((v) => (v * 1e6).round() / 1e6), [52, 20]);
      expect(box.height, closeTo(3, 1e-9));
    });

    test('sphere diameter and cone base radius come from the matrix and params', () {
      final sp = load([shape('sphere', xf(0, 0, 0, sx: 1.5, sy: 1.5, sz: 1.5))]).document.roots.single as ShapeNode;
      expect([sp.kind, sp.width], [ShapeKind.sphere, 30]);
      final cone = load([shape('cone', xf(0, 0, 0, sz: 2), params: {'base': 5, 'top': 0})]).document.roots.single as ShapeNode;
      expect([cone.kind, cone.width, cone.height], [ShapeKind.cone, 10, 40]);
    });

    test('rotation is carried across, and rotating swaps nothing about size', () {
      final s = load([shape('box', xf(0, 0, 0, rz: 90, sx: 3, sy: 1))]).document.roots.single as ShapeNode;
      expect([s.width, s.depth].map((v) => (v * 1e6).round() / 1e6), [60, 20]);
      expect(s.placement.rz, closeTo(90, 1e-9));
    });

    test('hole shapes and hole groups keep their flag; group mode maps across', () {
      final r = load([
        grp([shape('box', Mat4.identity), shape('cylinder', Mat4.identity, hole: true)], Mat4.identity, mode: 'intersect'),
        grp([shape('box', Mat4.identity)], Mat4.identity, mode: 'bundle', hole: true),
      ]);
      final g = r.document.roots[0] as GroupNode;
      expect(g.op, GroupOp.intersect);
      expect((g.children[1] as ShapeNode).isHole, isTrue);
      expect((r.document.roots[1] as GroupNode).op, GroupOp.bundle);
      expect(r.document.roots[1].isHole, isTrue);
    });

    test('colours: #rgb shorthand, bad values fall back', () {
      expect(load([shape('box', Mat4.identity, color: '#f80')]).document.roots.single.color, 0xFFFF8800);
      expect(load([shape('box', Mat4.identity, color: 'red')]).document.roots.single.color, 0xFF3B82F6);
      expect(load([shape('box', Mat4.identity, color: '#12345')]).document.roots.single.color, 0xFF3B82F6);
    });
  });

  group('world-space equivalence (the important one)', () {
    test('random shapes: every corner lands where DabbleCAD put it', () {
      final rnd = math.Random(7);
      double r(double lo, double hi) => lo + rnd.nextDouble() * (hi - lo);
      for (var i = 0; i < 200; i++) {
        final m = xf(r(-80, 80), r(-80, 80), r(0, 40), rx: r(-180, 180), ry: r(-80, 80), rz: r(-180, 180), sx: r(0.2, 4), sy: r(0.2, 4), sz: r(0.2, 4));
        final s = load([shape('box', m)]).document.roots.single as ShapeNode;
        expect(sorted(empuCorners(s, const [])), sorted(dabbleCorners(m)), reason: 'iteration $i');
      }
    });

    test('shapes inside groups with translation, rotation and UNIFORM scale', () {
      final rnd = math.Random(11);
      double r(double lo, double hi) => lo + rnd.nextDouble() * (hi - lo);
      for (var i = 0; i < 100; i++) {
        final k = r(0.3, 3);
        final gm = xf(r(-50, 50), r(-50, 50), r(0, 30), rx: r(-60, 60), ry: r(-60, 60), rz: r(-180, 180), sx: k, sy: k, sz: k);
        final cm = xf(r(-20, 20), r(-20, 20), r(0, 20), rx: r(-90, 90), ry: r(-90, 90), rz: r(-180, 180), sx: r(0.3, 2), sy: r(0.3, 2), sz: r(0.3, 2));
        final res = load([grp([shape('box', cm)], gm)]);
        expect(res.warnings, isEmpty, reason: 'uniform group scale cannot shear');
        final g = res.document.roots.single as GroupNode;
        expect(sorted(empuCorners(g.children.single as ShapeNode, [g])), sorted(dabbleCorners(gm * cm)), reason: 'iteration $i');
      }
    });

    test('a NON-uniform group scale is pushed into its children, exactly when they are axis-aligned', () {
      final gm = xf(5, 6, 7, sx: 2, sy: 3, sz: 0.5);
      final cm = xf(10, -4, 2, rz: 90, sx: 1.5, sy: 0.7, sz: 2); // rotated by a multiple of 90 degrees about Z
      final res = load([grp([shape('box', cm)], gm)]);
      expect(res.warnings, isEmpty);
      final g = res.document.roots.single as GroupNode;
      expect([g.placement.x, g.placement.y, g.placement.z], [5, 6, 7]);
      expect(sorted(empuCorners(g.children.single as ShapeNode, [g])), sorted(dabbleCorners(gm * cm)));
    });

    test('nested groups compose correctly', () {
      final outer = xf(10, 0, 0, rz: 30, sx: 2, sy: 2, sz: 2);
      final inner = xf(0, 5, 1, rz: -45, sx: 0.5, sy: 0.5, sz: 0.5);
      final leaf = xf(3, 3, 3, rx: 20, ry: 10, rz: 5, sx: 1.2, sy: 0.8, sz: 1.1);
      final res = load([grp([grp([shape('box', leaf)], inner)], outer)]);
      final g1 = res.document.roots.single as GroupNode;
      final g2 = g1.children.single as GroupNode;
      expect(sorted(empuCorners(g2.children.single as ShapeNode, [g1, g2])), sorted(dabbleCorners(outer * inner * leaf)));
    });

    test('a rotated child under a non-uniform group scale is flagged as skewed, not silently wrong', () {
      final res = load([grp([shape('box', xf(0, 0, 0, rz: 30))], xf(0, 0, 0, sx: 2, sy: 1, sz: 1))]);
      expect(res.warnings.any((w) => w.contains('skewed')), isTrue, reason: '${res.warnings}');
    });

    test('a mirrored shape is exact (symmetric shapes), a mirrored group is flagged', () {
      final m = xf(4, 5, 6, rz: 20, sx: -1.5, sy: 1, sz: 1);
      final s = load([shape('box', m)]).document.roots.single as ShapeNode;
      expect(sorted(empuCorners(s, const [])), sorted(dabbleCorners(m)));
      final res = load([grp([shape('box', Mat4.identity)], xf(0, 0, 0, sx: -1))]);
      expect(res.warnings.any((w) => w.contains('mirrored')), isTrue);
    });
  });

  group('what cannot come across is reported', () {
    test('unsupported kinds, hidden shapes and empty groups', () {
      final r = load([
        shape('roof', Mat4.identity),
        shape('roof', Mat4.identity),
        shape('torus', Mat4.identity),
        shape('box', Mat4.identity, hidden: true),
        grp([shape('text', Mat4.identity)], Mat4.identity),
        shape('box', Mat4.identity),
      ]);
      expect(r.document.roots, hasLength(1));
      expect(r.warnings.any((w) => w.contains('roof x2') && w.contains('torus x1') && w.contains('text x1')), isTrue, reason: '${r.warnings}');
      expect(r.warnings.any((w) => w.contains('hidden')), isTrue);
      expect(r.warnings.any((w) => w.contains('group') && w.contains('Dropped')), isTrue);
    });

    test('rounded boxes, bevels, few-sided cylinders, frustums, ellipsoids are simplified with a warning each', () {
      final r = load([
        shape('box', Mat4.identity, params: {'radius': 3}),
        shape('cylinder', Mat4.identity, params: {'bevel': 2}),
        shape('cylinder', Mat4.identity, params: {'sides': 6}),
        shape('cone', Mat4.identity, params: {'top': 4, 'base': 10}),
        shape('sphere', xf(0, 0, 0, sx: 1, sy: 1, sz: 2)),
        shape('cylinder', xf(0, 0, 0, sx: 1, sy: 2)),
      ]);
      expect(r.document.roots, hasLength(6));
      final text = r.warnings.join('\n');
      for (final needle in ['Rounded', 'few sides', 'flat top', 'squashed', 'stretched unevenly']) {
        expect(text, contains(needle));
      }
    });

    test('a clean file produces no warnings at all', () {
      expect(load([shape('box', xf(1, 2, 3, rz: 15, sx: 2)), shape('sphere', Mat4.identity)]).warnings, isEmpty);
    });
  });

  group('laser layers', () {
    test('layers 1 to 5 take speed, power, passes, fill settings; the rest is reported', () {
      final r = load([shape('box', Mat4.identity)], laser: {
        'shapes': [{}, {}, {}],
        'layers': {
          '0': {'mode': 'line', 'speed': 7, 'powerMax': 85, 'passes': 2, 'interval': 0.1, 'overscan': 1.5, 'bidirectional': false},
          '2': {'mode': 'fill', 'speed': 150, 'powerMax': 40, 'interval': 0.07, 'angle': 45, 'passes': 1, 'overscan': 3},
          '7': {'mode': 'line', 'speed': 1, 'powerMax': 1},
        },
      });
      final l0 = r.document.laser.layer(0)!, l2 = r.document.laser.layer(2)!;
      expect([l0.speed, l0.power, l0.passes, l0.overscan, l0.bidirectional], [7, 85, 2, 1.5, false]);
      expect([l2.mode, l2.speed, l2.power, l2.interval, l2.angle], [LaserLayerMode.fill, 150, 40, 0.07, 45]);
      expect(r.document.laser.layer(1)!.speed, LaserSetup.defaultLayers[1].speed, reason: 'absent layers keep defaults');
      final w = r.warnings.join('\n');
      expect(w, contains('3 laser shapes'));
      expect(w, contains('layers 6 and up'));
    });

    test('nonsense layer values fall back to defaults instead of breaking the document', () {
      final r = load([shape('box', Mat4.identity)], laser: {
        'layers': {'0': {'speed': -5, 'powerMax': 500, 'passes': 0, 'interval': 0}},
      });
      final l = r.document.laser.layer(0)!;
      expect(l.speed, LaserSetup.defaultLayers[0].speed);
      expect(l.power, 100, reason: 'power is clamped to 100');
      expect(l.passes, 1);
      expect(l.interval, LaserSetup.defaultLayers[0].interval);
    });

    test('no laser block is fine', () {
      expect(load([shape('box', Mat4.identity)]).document.laser.layers, hasLength(5));
    });
  });

  group('bad files', () {
    for (final (label, text) in [
      ('not JSON', '{oops'),
      ('a different app', '{"app":"Other","nodes":[]}'),
      ('no nodes', '{"app":"DabbleCAD"}'),
      ('bad matrix', '{"app":"DabbleCAD","nodes":[{"type":"shape","kind":"box","matrix":[1,2,3]}]}'),
      ('node not an object', '{"app":"DabbleCAD","nodes":[5]}'),
      ('group without children', '{"app":"DabbleCAD","nodes":[{"type":"group"}]}'),
    ]) {
      test('rejects: $label', () => expect(() => DabbleImporter.fromText(text), throwsA(isA<FormatException>())));
    }

    test('absurd nesting is refused instead of overflowing the stack', () {
      Map<String, Object?> nest(int d) => {'type': 'group', 'children': d == 0 ? [] : [nest(d - 1)]};
      expect(() => DabbleImporter.fromText(jsonEncode({'app': 'DabbleCAD', 'nodes': [nest(200)]})), throwsA(isA<FormatException>()));
    });
  });

  group('DocumentOpener', () {
    test('recognises a DabbleCAD file by content and an EmpuCAD file by content', () {
      final d = DocumentOpener.open(jsonEncode({'app': 'DabbleCAD', 'name': 'x', 'nodes': [shape('box', Mat4.identity)]}));
      expect(d.source, DocumentSource.dabbleCad);
      expect(d.document.roots, hasLength(1));
      final e = DocumentOpener.open('{"app":"EmpuCAD","version":1,"nodes":[]}');
      expect(e.source, DocumentSource.empucad);
      expect(e.warnings, isEmpty);
      expect(() => DocumentOpener.open('{"app":"Nope"}'), throwsA(isA<FormatException>()));
      expect(() => DocumentOpener.open('garbage'), throwsA(isA<FormatException>()));
    });

    test('an imported design builds into meshes through the normal pipeline', () async {
      final d = DocumentOpener.open(jsonEncode({
        'app': 'DabbleCAD',
        'nodes': [grp([shape('box', xf(0, 0, 0, sx: 3)), shape('cylinder', xf(0, 0, 0, sx: 0.5, sy: 0.5), hole: true)], xf(10, 10, 0))],
      })).document;
      final r = await SceneEvaluator(FakeGeometryEngine()).evaluate(d);
      expect(r.warnings, isEmpty);
      expect(r.items, hasLength(1), reason: 'union with a subtracted hole is one solid');
    });
  });
}
