import 'dart:math' as math;

import 'package:empucad/application/arrange.dart';
import 'package:empucad/application/document_ops.dart';
import 'package:empucad/application/mesh_tools.dart';
import 'package:empucad/application/node_bounds.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/core/math/mat4.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/outline.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

ShapeNode box(String id, {double x = 0, double y = 0, double z = 0, double w = 10, double d = 10, double h = 10, double rz = 0}) =>
    ShapeNode(id: id, name: id, kind: ShapeKind.box, width: w, depth: d, height: h, placement: Placement(x: x, y: y, z: z, rz: rz));

String Function() counter([String prefix = 'c']) {
  var n = 0;
  return () => '$prefix${++n}';
}

void expectNear(num a, num b, [double eps = 1e-9]) => expect(a, closeTo(b, eps));

/// Every value equals [v] (within 1e-9).
void allEqual(Iterable<num> values, num v) {
  for (final x in values) {
    expect(x, closeTo(v, 1e-9));
  }
}

void expectSameMatrix(Mat4 a, Mat4 b, {double eps = 1e-9}) {
  for (var i = 0; i < 16; i++) {
    expect(a.m[i], closeTo(b.m[i], eps), reason: 'element $i');
  }
}

void main() {
  group('NodeBounds', () {
    test('a box: size and placement; z runs from the base up', () {
      final b = NodeBounds.of(box('a', x: 10, y: 20, z: 5, w: 4, d: 6, h: 8))!;
      expect([b.minX, b.maxX, b.minY, b.maxY, b.minZ, b.maxZ], [8, 12, 17, 23, 5, 13]);
    });

    test('rotating 90 degrees about Z swaps width and depth', () {
      final b = NodeBounds.of(box('a', w: 4, d: 6, rz: 90))!;
      expectNear(b.width, 6);
      expectNear(b.depth, 4);
    });

    test('groups union their children and apply their own placement', () {
      final g = GroupNode(id: 'g', name: 'g', placement: const Placement(x: 100), children: [box('a'), box('b', x: 30)]);
      final b = NodeBounds.of(g)!;
      expect([b.minX, b.maxX], [95, 135]);
      expect(NodeBounds.of(GroupNode(id: 'e', name: 'e', children: const [])), isNull);
    });

    test('outline nodes use their points and their thickness; meshes use their scaled vertices', () async {
      final o = OutlineNode(id: 'o', name: 'o', height: 4, placement: const Placement(x: 1), shapes: const [ShapeOutlines([Outline([0, 0, 10, 0, 10, 20, 0, 20])])]);
      final ob = NodeBounds.of(o)!;
      expect([ob.minX, ob.maxX, ob.minY, ob.maxY, ob.minZ, ob.maxZ], [1, 11, 0, 20, 0, 4]);
      final cube = await FakeGeometryEngine().primitive(ShapeKind.box, width: 10, depth: 10, height: 10);
      final mesh = MeshNode.fromMesh(id: 'm', name: 'm', mesh: MeshTools.restOnWorkplane(cube)).resized(width: 40, keepAspect: true);
      final mb = NodeBounds.of(mesh)!;
      expect([mb.minX, mb.maxX, mb.minZ, mb.maxZ], [-20, 20, 0, 40]);
    });
  });

  group('clone', () {
    test('every node in a tree gets a fresh id, content is identical', () {
      final g = GroupNode(id: 'g', name: 'g', op: GroupOp.intersect, placement: const Placement(x: 3), children: [box('a'), GroupNode(id: 'g2', name: 'g2', children: [box('b', x: 5)])]);
      final map = <String, String>{};
      final c = Arrange.clone(g, counter(), map) as GroupNode;
      expect(map.keys.toSet(), {'g', 'a', 'g2', 'b'});
      expect(map.values.toSet().length, 4, reason: 'all new ids distinct');
      expect(map.values.any(map.keys.contains), isFalse, reason: 'none reuse an old id');
      expect(c.geometryKey, g.geometryKey);
      expect(c.op, GroupOp.intersect);
    });
  });

  group('linear array and duplicate', () {
    final base = Document(roots: [box('a', x: 5), box('b', x: 50)]);

    test('copy i is offset by i times the step; originals are untouched; order is copy by copy', () {
      final r = Arrange.linear(base, {'a'}, count: 3, dx: 25, dy: 1, nextId: counter());
      expect(r.newIds, hasLength(3));
      expect(r.document.roots.length, 5);
      expect([for (final id in r.newIds) r.document.find(id)!.placement.x], [30, 55, 80]);
      expect([for (final id in r.newIds) r.document.find(id)!.placement.y], [1, 2, 3]);
      expect(r.document.find('a')!.placement.x, 5);
      expect(r.document.roots.sublist(0, 2).map((n) => n.id), ['a', 'b']);
    });

    test('several selected nodes are copied together, copy by copy', () {
      final r = Arrange.linear(base, {'a', 'b'}, count: 2, dx: 100, nextId: counter());
      expect([for (final id in r.newIds) r.document.find(id)!.placement.x], [105, 150, 205, 250]);
    });

    test('nothing happens for count 0, an empty selection, or ids that are not top-level', () {
      expect(Arrange.linear(base, {'a'}, count: 0, nextId: counter()).newIds, isEmpty);
      expect(Arrange.linear(base, {}, count: 2, nextId: counter()).newIds, isEmpty);
      final nested = Document(roots: [GroupNode(id: 'g', name: 'g', children: [box('k')])]);
      expect(Arrange.linear(nested, {'k'}, count: 2, nextId: counter()).newIds, isEmpty, reason: 'nested ids are ignored');
    });

    test('duplicate makes one copy offset by 10, 10 and returns its id', () {
      final r = Arrange.duplicate(base, {'a'}, nextId: counter());
      final c = r.document.find(r.newIds.single)!;
      expect([c.placement.x, c.placement.y], [15, 10]);
    });

    test('copying a group copies its children with unique ids, and laser layers come along', () {
      var d = Document(roots: [GroupNode(id: 'g', name: 'g', children: [box('a'), box('b', x: 20)])]);
      d = DocumentOps.assignLayer(d, {'g'}, 2);
      d = DocumentOps.assignLayer(d, {'a'}, 3);
      final r = Arrange.linear(d, {'g'}, count: 1, dx: 50, nextId: counter());
      final ids = r.document.allNodes.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'no id collisions');
      final copy = r.document.find(r.newIds.single) as GroupNode;
      expect(r.document.laser.layerOf[copy.id], 2);
      expect(r.document.laser.layerOf[copy.children.first.id], 3, reason: 'the child that had its own layer keeps it');
      expect(r.document.laser.layerOf['g'], 2);
    });

    test('an arrayed design evaluates to one distinct mesh per copy', () async {
      final r = Arrange.linear(Document(roots: [box('a')]), {'a'}, count: 4, dx: 20, nextId: counter());
      final items = (await SceneEvaluator(FakeGeometryEngine()).evaluate(r.document)).items;
      expect(items.length, 5);
      expect(items.map((i) => i.nodeId).toSet().length, 5);
    });
  });

  group('grid array', () {
    test('2 rows x 3 columns: the original is cell (0,0), five copies fill the rest', () {
      final d = Document(roots: [box('a', x: 1, y: 2)]);
      final r = Arrange.grid(d, {'a'}, rows: 2, columns: 3, dx: 10, dy: 20, nextId: counter());
      final pos = {for (final id in r.newIds) (r.document.find(id)!.placement.x, r.document.find(id)!.placement.y)};
      expect(pos, {(11.0, 2.0), (21.0, 2.0), (1.0, 22.0), (11.0, 22.0), (21.0, 22.0)});
      expect(Arrange.grid(d, {'a'}, rows: 1, columns: 1, dx: 1, dy: 1, nextId: counter()).newIds, isEmpty);
    });
  });

  group('circular array', () {
    test('four copies around the origin sit 72 degrees apart on the same radius (full circle = five items)', () {
      final d = Document(roots: [box('a', x: 30)]);
      final r = Arrange.circular(d, {'a'}, count: 4, cx: 0, cy: 0, nextId: counter());
      for (var i = 0; i < 4; i++) {
        final p = r.document.find(r.newIds[i])!.placement;
        final a = 72.0 * (i + 1) * math.pi / 180;
        expectNear(p.x, 30 * math.cos(a), 1e-9);
        expectNear(p.y, 30 * math.sin(a), 1e-9);
      }
    });

    test('an arc: 3 copies spread over 90 degrees are at 30, 60 and 90 degrees', () {
      final d = Document(roots: [box('a', x: 10)]);
      final r = Arrange.circular(d, {'a'}, count: 3, cx: 0, cy: 0, totalAngle: 90, nextId: counter());
      final ang = [for (final id in r.newIds) math.atan2(r.document.find(id)!.placement.y, r.document.find(id)!.placement.x) * 180 / math.pi];
      expectNear(ang[0], 30, 1e-9);
      expectNear(ang[1], 60, 1e-9);
      expectNear(ang[2], 90, 1e-9);
    });

    test('the whole world matrix of each copy is the original turned about the centre, even for tilted nodes', () {
      final original = ShapeNode(id: 'a', name: 'a', kind: ShapeKind.box, width: 6, depth: 4, height: 8, placement: const Placement(x: 25, y: -7, z: 3, rx: 20, ry: -35, rz: 40));
      const cx = 12.0, cy = 5.0;
      final r = Arrange.circular(Document(roots: [original]), {'a'}, count: 5, cx: cx, cy: cy, nextId: counter());
      for (var i = 1; i <= 5; i++) {
        final turn = Mat4.translation(cx, cy, 0) * Mat4.rotationZ(60.0 * i) * Mat4.translation(-cx, -cy, 0);
        expectSameMatrix(r.document.find(r.newIds[i - 1])!.placement.toMatrix(), turn * original.placement.toMatrix(), eps: 1e-8);
      }
    });

    test('a node at the centre only spins in place', () {
      final r = Arrange.circular(Document(roots: [box('a')]), {'a'}, count: 3, cx: 0, cy: 0, nextId: counter());
      final p = r.document.find(r.newIds[0])!.placement;
      expectNear(p.x, 0);
      expectNear(p.rz, 90);
    });
  });

  group('align', () {
    // widths 10, 20, 30 at different places, different heights
    Document three() => Document(roots: [box('a', x: 0, y: 0, z: 0, w: 10, d: 10, h: 10), box('b', x: 50, y: 30, z: 5, w: 20, d: 6, h: 20), box('c', x: 20, y: -40, z: 2, w: 30, d: 12, h: 4)]);
    Bounds bd(Document d, String id) => NodeBounds.of(d.find(id)!)!;
    final all = {'a', 'b', 'c'};

    test('left, right and centre in X line the bounds up on the selection\'s edge or middle', () {
      final d = three();
      final lo = [for (final id in all) bd(d, id).minX].reduce((a, b) => a < b ? a : b);
      final hi = [for (final id in all) bd(d, id).maxX].reduce((a, b) => a > b ? a : b);
      final l = Arrange.align(d, all, AlignMode.left);
      allEqual([for (final id in all) bd(l, id).minX], lo);
      final r = Arrange.align(d, all, AlignMode.right);
      allEqual([for (final id in all) bd(r, id).maxX], hi);
      final c = Arrange.align(d, all, AlignMode.centerX);
      allEqual([for (final id in all) bd(c, id).centerX], (lo + hi) / 2);
    });

    test('front, back and centre in Y', () {
      final d = three();
      final f = Arrange.align(d, all, AlignMode.front);
      allEqual([for (final id in all) bd(f, id).minY], -46);
      final b = Arrange.align(d, all, AlignMode.back);
      allEqual([for (final id in all) bd(b, id).maxY], 33);
      final c = Arrange.align(d, all, AlignMode.centerY);
      allEqual([for (final id in all) bd(c, id).centerY], -6.5);
    });

    test('base and top in Z', () {
      final d = three();
      final b = Arrange.align(d, all, AlignMode.base);
      allEqual([for (final id in all) bd(b, id).minZ], 0);
      final t = Arrange.align(d, all, AlignMode.top);
      allEqual([for (final id in all) bd(t, id).maxZ], 25);
    });

    test('rotated shapes and groups align by their real bounds, and unselected nodes do not move', () {
      final d = Document(roots: [box('r', x: 100, w: 4, d: 20, rz: 90), GroupNode(id: 'g', name: 'g', placement: const Placement(x: -50), children: [box('k', w: 10)]), box('other', x: 7)]);
      final l = Arrange.align(d, {'r', 'g'}, AlignMode.left);
      expectNear(bd(l, 'r').minX, bd(l, 'g').minX);
      expect(l.find('other')!.placement.x, 7);
    });

    test('fewer than two nodes, or no change needed, returns the same document', () {
      final d = three();
      expect(identical(Arrange.align(d, {'a'}, AlignMode.left), d), isTrue);
      expect(identical(Arrange.align(d, {}, AlignMode.left), d), isTrue);
      final once = Arrange.align(d, all, AlignMode.left);
      final twice = Arrange.align(once, all, AlignMode.left);
      expect([for (final id in all) twice.find(id)!.placement.x], [for (final id in all) once.find(id)!.placement.x], reason: 'idempotent');
    });
  });
}
