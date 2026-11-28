import 'dart:convert';
import 'dart:typed_data';

import 'package:empucad/application/footprint.dart';
import 'package:empucad/application/import_stl.dart';
import 'package:empucad/application/mesh_tools.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/data/codec/mesh_codec.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/domain/ports/geometry_engine.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

/// A 10 x 20 x 30 box whose corner is at (100, 200, 50): nowhere near the origin.
Future<MeshData> offsetBox(FakeGeometryEngine e) async {
  final m = await e.primitive(ShapeKind.box, width: 10, depth: 20, height: 30);
  final p = Float32List.fromList(m.positions);
  for (var i = 0; i < p.length; i += 3) {
    p[i] += 105;
    p[i + 1] += 210;
    p[i + 2] += 65;
  }
  return MeshData(p, m.indices);
}

List<double> bounds(MeshData m) {
  final lo = [double.infinity, double.infinity, double.infinity], hi = [-double.infinity, -double.infinity, -double.infinity];
  for (var i = 0; i < m.positions.length; i += 3) {
    for (var k = 0; k < 3; k++) {
      lo[k] = lo[k] < m.positions[i + k] ? lo[k] : m.positions[i + k];
      hi[k] = hi[k] > m.positions[i + k] ? hi[k] : m.positions[i + k];
    }
  }
  return [...lo, ...hi];
}

void main() {
  late FakeGeometryEngine engine;
  setUp(() => engine = FakeGeometryEngine());

  group('MeshTools', () {
    test('restOnWorkplane centres X/Y, puts the lowest point on z = 0, and does not touch the input', () async {
      final raw = await offsetBox(engine);
      final before = bounds(raw);
      final moved = MeshTools.restOnWorkplane(raw);
      final b = bounds(moved);
      expect([b[0], b[3]], [-5, 5]);
      expect([b[1], b[4]], [-10, 10]);
      expect([b[2], b[5]], [0, 30]);
      expect(bounds(raw), before, reason: 'input unchanged');
      expect(identical(moved.indices, raw.indices), isTrue, reason: 'topology is shared, not copied');
    });

    test('convex hull of a point cloud is the CCW outline; interior and collinear points vanish', () {
      final pts = <double>[0, 0, 10, 0, 10, 10, 0, 10, 5, 5, 5, 0, 10, 5, 2, 2, 0, 0];
      final h = MeshTools.convexHull(pts);
      expect(h, [0, 0, 10, 0, 10, 10, 0, 10]);
      expect(MeshTools.convexHull([1, 1, 2, 2]), [1, 1, 2, 2], reason: 'too few points: returned as is');
      expect(MeshTools.convexHull([]), isEmpty);
      expect(MeshTools.convexHull([0, 0, 1, 1, 2, 2, 3, 3]).length <= 8, isTrue);
    });
  });

  group('ImportStl', () {
    test('a decoded mesh becomes a node resting on the workplane, with no warnings when it is closed', () async {
      engine.stlResult = await offsetBox(engine);
      final r = await ImportStl(engine)(Uint8List(4), id: 'm1', name: 'Bracket');
      expect(r.warnings, isEmpty);
      expect(r.node.name, 'Bracket');
      final b = bounds(r.node.mesh);
      expect([b[2], b[5]], [0, 30]);
      expect([b[0], b[3]], [-5, 5]);
    });

    test('an open mesh still imports but is warned about; an inside-out one is flagged', () async {
      engine.stlResult = await offsetBox(engine);
      engine.report = const SolidReport(closed: false, volume: 0, surfaceArea: 0);
      expect((await ImportStl(engine)(Uint8List(4), id: 'a')).warnings.single, contains('not a closed solid'));
      engine.report = const SolidReport(closed: true, volume: -5, surfaceArea: 10);
      expect((await ImportStl(engine)(Uint8List(4), id: 'a')).warnings.single, contains('inside out'));
    });

    test('empty and oversized files are refused with a readable message', () async {
      Object? e1, e2;
      try {
        await ImportStl(engine)(Uint8List(4), id: 'a'); // fake returns an empty mesh by default
      } on InvalidInputFailure catch (e) {
        e1 = e;
      }
      expect(e1.toString(), contains('no triangles'));
      engine.stlResult = MeshData(Float32List(9), Uint32List(ImportStl.maxTriangles * 3 + 3));
      try {
        await ImportStl(engine)(Uint8List(4), id: 'a');
      } on InvalidInputFailure catch (e) {
        e2 = e;
      }
      expect(e2.toString(), contains('limit'));
    });
  });

  group('MeshNode', () {
    late MeshNode node;
    setUp(() async {
      node = MeshNode.fromMesh(id: 'm', name: 'M', mesh: MeshTools.restOnWorkplane(await offsetBox(engine)));
    });

    test('moving or renaming keeps the mesh fingerprint; changing the mesh changes the key', () async {
      final moved = node.withPlacement(const Placement(x: 5));
      expect(moved.meshHash, node.meshHash);
      expect(moved.geometryKey == node.geometryKey, isFalse);
      expect(node.withName('other').geometryKey, node.geometryKey);
      final other = MeshNode.fromMesh(id: 'm', name: 'M', mesh: await engine.primitive(ShapeKind.box, width: 1, depth: 1, height: 1));
      expect(other.geometryKey == node.geometryKey, isFalse);
    });

    test('the evaluator places it by its placement only, and caches it across edits that do not touch it', () async {
      final ev = SceneEvaluator(engine);
      var doc = Document(roots: [node.withPlacement(const Placement(x: 50, y: 60, z: 7)), ShapeNode(id: 's', name: 's', kind: ShapeKind.box, width: 5, depth: 5, height: 5)]);
      final r = await ev.evaluate(doc);
      final b = bounds(r.items.first.mesh);
      expect([b[0], b[3]], [45, 55]);
      expect([b[2], b[5]], [7, 37]);
      final first = ev.computeCount;
      doc = doc.updateNode('s', (n) => n.withName('renamed'));
      await ev.evaluate(doc);
      expect(ev.computeCount, first, reason: 'nothing recomputed');
    });

    test('its CAM/laser footprint is the silhouette seen from above, placement and rotation applied', () {
      final fp = Footprint.of(Document(roots: [node.withPlacement(const Placement(x: 100, rz: 90))])).single.outlines.single;
      final xs = [for (var i = 0; i < fp.points.length; i += 2) fp.points[i]];
      final ys = [for (var i = 0; i < fp.points.length; i += 2) fp.points[i + 1]];
      // 10 x 20 footprint rotated 90 degrees about Z: spans 20 in X, 10 in Y, centred on x = 100
      expect([xs.reduce((a, b) => a < b ? a : b), xs.reduce((a, b) => a > b ? a : b)].map((v) => v.round()), [90, 110]);
      expect([ys.reduce((a, b) => a < b ? a : b), ys.reduce((a, b) => a > b ? a : b)].map((v) => v.round()), [-5, 5]);
      expect(fp.points.length, 8, reason: 'a box silhouette is a quadrilateral');
    });
  });

  group('MeshCodec and the document file', () {
    test('a mesh survives save and open bit for bit, with its placement', () async {
      final m = MeshTools.restOnWorkplane(await offsetBox(engine));
      final d = Document(roots: [MeshNode.fromMesh(id: 'm', name: 'Part', mesh: m, placement: const Placement(x: 3, rz: 45), color: 0xFF112233)]);
      final back = DocumentCodec.decode(DocumentCodec.encode(d)).roots.single as MeshNode;
      expect(back.mesh.positions, m.positions);
      expect(back.mesh.indices, m.indices);
      expect(back.placement.rz, 45);
      expect(back.color, 0xFF112233);
      expect(back.geometryKey, d.roots.single.geometryKey);
    });

    Map<String, Object?> good() => MeshCodec.encode(MeshData(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]), Uint32List.fromList([0, 1, 2])));

    test('rejects corrupt meshes: bad sizes, bad base64, out-of-range indices, NaN', () {
      expect(MeshCodec.decode(good()).triangleCount, 1);
      Map<String, dynamic> tweak(String k, Object? v) => {...good(), k: v};
      for (final (label, bad) in [
        ('too few vertices', tweak('vertices', 2)),
        ('zero triangles', tweak('triangles', 0)),
        ('absurd triangle count', tweak('triangles', 99999999)),
        ('size mismatch', tweak('vertices', 4)),
        ('not base64', tweak('positions', '!!!')),
        ('missing field', {...good()}..remove('indices')),
        ('index past the end', tweak('indices', base64Encode((ByteData(12)..setUint32(0, 0, Endian.little)..setUint32(4, 1, Endian.little)..setUint32(8, 3, Endian.little)).buffer.asUint8List()))),
        ('NaN coordinate', tweak('positions', base64Encode((ByteData(36)..setFloat32(0, double.nan, Endian.little)).buffer.asUint8List()))),
      ]) {
        expect(() => MeshCodec.decode(bad), throwsA(isA<FormatException>()), reason: label);
      }
    });

    test('byte order is fixed (little endian) so files are portable', () {
      final j = MeshCodec.encode(MeshData(Float32List.fromList([1, 0, 0, 0, 0, 0, 0, 0, 0]), Uint32List.fromList([0, 1, 2])));
      // 1.0f little endian = 00 00 80 3F
      expect(base64Decode(j['positions'] as String).sublist(0, 4), [0, 0, 0x80, 0x3F]);
      expect(base64Decode(j['indices'] as String).sublist(0, 12), [0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0]);
    });

    test('a document with a corrupt mesh node is rejected as a whole', () {
      final text = DocumentCodec.encode(Document(roots: [MeshNode.fromMesh(id: 'm', name: 'M', mesh: MeshData(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]), Uint32List.fromList([0, 1, 2])))]));
      final broken = text.replaceFirst('"triangles": 1', '"triangles": 5');
      expect(broken == text, isFalse);
      expect(() => DocumentCodec.decode(broken), throwsA(isA<FormatException>()));
    });
  });
}
