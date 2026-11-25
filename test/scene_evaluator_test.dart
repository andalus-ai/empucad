import 'package:empucad/application/export_stl.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/ports/geometry_engine.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

ShapeNode box(String id, {double z = 0, bool hole = false, double h = 10}) =>
    ShapeNode(id: id, name: id, kind: ShapeKind.box, width: 10, depth: 10, height: h, placement: Placement(z: z), isHole: hole);

void main() {
  identicalShapesKeepTheirIds();
  exportTests();
  late FakeGeometryEngine engine;
  late SceneEvaluator ev;
  setUp(() {
    engine = FakeGeometryEngine();
    ev = SceneEvaluator(engine);
  });

  test('a shape rests on the workplane: placement.z is its bottom', () async {
    final r = await ev.evaluate(Document(roots: [box('a', z: 4, h: 10)]));
    final zs = [for (var i = 2; i < r.items.single.mesh.positions.length; i += 3) r.items.single.mesh.positions[i]];
    expect(zs.reduce((a, b) => a < b ? a : b), closeTo(4, 1e-6));
    expect(zs.reduce((a, b) => a > b ? a : b), closeTo(14, 1e-6));
  });

  test('a group sends solids and holes to ONE boolean call and yields one item', () async {
    final g = GroupNode(id: 'g', name: 'g', children: [box('s1'), box('s2'), box('h', hole: true)]);
    final r = await ev.evaluate(Document(roots: [g]));
    expect(engine.booleanCalls, hasLength(1));
    expect(engine.booleanCalls.single.solids, 2);
    expect(engine.booleanCalls.single.holes, 1);
    expect(engine.booleanCalls.single.mode, BooleanMode.union);
    expect(r.items.map((i) => i.nodeId), ['g']);
  });

  test('intersect groups use intersect mode', () async {
    final g = GroupNode(id: 'g', name: 'g', op: GroupOp.intersect, children: [box('a'), box('b')]);
    await ev.evaluate(Document(roots: [g]));
    expect(engine.booleanCalls.single.mode, BooleanMode.intersect);
  });

  test('bundle groups never call boolean', () async {
    final g = GroupNode(id: 'g', name: 'g', op: GroupOp.bundle, children: [box('a'), box('b')]);
    final r = await ev.evaluate(Document(roots: [g]));
    expect(engine.booleanCalls, isEmpty);
    expect(r.items.map((i) => i.nodeId), ['a', 'b']);
  });

  test('a rejected boolean degrades to showing the parts, with a warning', () async {
    engine.failBooleanWith = const NotWatertightFailure('open mesh');
    final g = GroupNode(id: 'g', name: 'Bracket', children: [box('a'), box('b')]);
    final r = await ev.evaluate(Document(roots: [g]));
    expect(r.items.map((i) => i.nodeId), ['a', 'b']);
    expect(r.warnings.single, contains('Bracket'));
  });

  test('renaming or recolouring does not recompute; moving one shape recomputes only its group', () async {
    final g = GroupNode(id: 'g', name: 'g', children: [box('a'), box('b')]);
    final other = box('z');
    var doc = Document(roots: [g, other]);
    await ev.evaluate(doc);
    final first = ev.computeCount;

    doc = doc.updateNode('a', (n) => n.withName('renamed').withColor(0xFFFF0000));
    await ev.evaluate(doc);
    expect(ev.computeCount, first, reason: 'name/colour are not part of geometryKey');

    doc = doc.updateNode('a', (n) => n.withPlacement(const Placement(x: 5)));
    await ev.evaluate(doc);
    // recomputed: shape a, group g. Not recomputed: shape b, shape z.
    expect(ev.computeCount, first + 2);
  });

  test('combinedSolid unions every non-hole item and ignores holes', () async {
    final doc = Document(roots: [box('a'), box('b', z: 20), box('h', hole: true)]);
    final m = await ev.combinedSolid(doc);
    expect(m, isNotNull);
    expect(engine.booleanCalls.single.solids, 2);
    expect(await SceneEvaluator(FakeGeometryEngine()).combinedSolid(const Document()), isNull);
  });
}

// Regression: identical shapes at the same placement share geometry but must keep their own ids.
void identicalShapesKeepTheirIds() {
  test('two identical shapes at the same place stay two distinct nodes', () async {
    final ev = SceneEvaluator(FakeGeometryEngine());
    final r = await ev.evaluate(Document(roots: [box('a'), box('b')]));
    expect(r.items.map((i) => i.nodeId), ['a', 'b']);
  });
}

void exportTests() {
  test('ExportStl returns null for an empty design and bytes otherwise', () async {
    final engine = FakeGeometryEngine();
    final export = ExportStl(SceneEvaluator(engine), engine);
    expect(await export(const Document()), isNull);
    expect(await export(Document(roots: [box('a')])), isNotNull);
  });
}
