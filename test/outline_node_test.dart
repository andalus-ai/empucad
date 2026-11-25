import 'package:empucad/application/footprint.dart';
import 'package:empucad/application/import_svg.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/outline.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/ports/geometry_engine.dart';
import 'package:empucad/domain/ports/svg_importer.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

const square = Outline([0, 0, 10, 0, 10, 10, 0, 10]);
OutlineNode node({String id = 'o', double h = 4, Placement p = Placement.origin, List<ShapeOutlines>? shapes}) =>
    OutlineNode(id: id, name: 'Logo', shapes: shapes ?? const [ShapeOutlines([square])], height: h, placement: p);

class _FakeImporter implements SvgImporter {
  _FakeImporter(this.shapes);
  final List<ShapeOutlines> shapes;
  @override
  Future<SvgImportResult> importSvg(String svg, {double toleranceMm = 0.05}) async => SvgImportResult(shapes: shapes, widthMm: 20, heightMm: 20);
}

void main() {
  test('an outline node extrudes from its placement upward (no half-height lift)', () async {
    final r = await SceneEvaluator(FakeGeometryEngine()).evaluate(Document(roots: [node(h: 4, p: const Placement(z: 2))]));
    final zs = [for (var i = 2; i < r.items.single.mesh.positions.length; i += 3) r.items.single.mesh.positions[i]];
    expect(zs.reduce((a, b) => a < b ? a : b), closeTo(2, 1e-6));
    expect(zs.reduce((a, b) => a > b ? a : b), closeTo(6, 1e-6));
  });

  test('several shapes are extruded separately then unioned', () async {
    final engine = FakeGeometryEngine();
    final two = [const ShapeOutlines([square]), const ShapeOutlines([Outline([20, 0, 30, 0, 30, 10, 20, 10])])];
    await SceneEvaluator(engine).evaluate(Document(roots: [node(shapes: two)]));
    expect(engine.extrudeCalls, 2);
    expect(engine.booleanCalls.single.solids, 2);
  });

  test('an unextrudable import is skipped with a warning instead of failing the scene', () async {
    final bad = node(shapes: const [ShapeOutlines([Outline([0, 0, 1, 1], closed: false)])]);
    final r = await SceneEvaluator(FakeGeometryEngine()).evaluate(Document(roots: [bad, node(id: 'ok')]));
    expect(r.items.map((i) => i.nodeId), ['ok']);
    expect(r.warnings.single, contains('Logo'));
  });

  test('geometry key changes with the outline content, not with the name', () {
    final a = node(), b = node();
    expect(a.geometryKey, b.geometryKey);
    expect(a.withName('other').geometryKey, a.geometryKey);
    final moved = node(shapes: const [ShapeOutlines([Outline([0, 0, 11, 0, 11, 10, 0, 10])])]);
    expect(moved.geometryKey == a.geometryKey, isFalse);
  });

  test('codec roundtrips outline nodes, including open outlines', () {
    final d = Document(roots: [
      node(p: const Placement(x: 3, rz: 90), shapes: const [
        ShapeOutlines([square, Outline([2, 2, 4, 2, 4, 4])]),
        ShapeOutlines([Outline([0, 0, 5, 5], closed: false)]),
      ]),
    ]);
    final back = DocumentCodec.decode(DocumentCodec.encode(d)).roots.single as OutlineNode;
    expect(back.height, 4);
    expect(back.placement.rz, 90);
    expect(back.shapes, hasLength(2));
    expect(back.shapes[0].outlines[1].points, [2, 2, 4, 2, 4, 4]);
    expect(back.shapes[1].outlines.single.closed, isFalse);
    expect(back.geometryKey, d.roots.single.geometryKey);
  });

  test('codec rejects malformed outline nodes', () {
    String doc(String shapes, [String h = '4']) =>
        '{"app":"EmpuCAD","version":1,"nodes":[{"type":"outline","id":"o","height":$h,"shapes":$shapes,"at":[0,0,0],"rot":[0,0,0]}]}';
    expect(() => DocumentCodec.decode(doc('[[{"closed":true,"pts":[0,0,1]}]]')), throwsA(isA<FormatException>()));
    expect(() => DocumentCodec.decode(doc('[[]]', '0')), throwsA(isA<FormatException>()));
    expect(() => DocumentCodec.decode(doc('"x"')), throwsA(isA<FormatException>()));
  });

  test('footprint of an outline node applies the placement and keeps open outlines open', () {
    final n = node(p: const Placement(x: 100), shapes: const [ShapeOutlines([square, Outline([0, 0, 1, 1], closed: false)])]);
    final fp = Footprint.of(Document(roots: [n])).single.outlines;
    expect(fp[0].points[0], closeTo(100, 1e-9));
    expect(fp[0].points[2], closeTo(110, 1e-9));
    expect(fp[1].closed, isFalse);
  });

  test('ImportSvg builds an extruded node and refuses an empty file', () async {
    final ok = await ImportSvg(_FakeImporter(const [ShapeOutlines([square])]))('<svg/>', id: 'n1', name: 'Logo', height: 5);
    expect(ok.height, 5);
    expect(ok.shapes, hasLength(1));
    Object? err;
    try {
      await ImportSvg(_FakeImporter(const []))('<svg/>', id: 'n2');
    } on InvalidInputFailure catch (e) {
      err = e;
    }
    expect(err, isNotNull);
  });
}
