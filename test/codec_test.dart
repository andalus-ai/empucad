import 'dart:convert';

import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:test/test.dart';

void main() {
  final doc = Document(name: 'Part', roots: [
    ShapeNode(id: 'a', name: 'Plate', kind: ShapeKind.box, width: 40, depth: 30, height: 5, placement: const Placement(x: 1, y: 2, z: 3, rz: 45), color: 0xFF112233),
    GroupNode(id: 'g', name: 'G', op: GroupOp.intersect, children: [
      ShapeNode.round(id: 'c', name: 'Hole', kind: ShapeKind.cylinder, diameter: 6, height: 10, isHole: true),
    ]),
  ]);

  test('roundtrip preserves every field', () {
    final back = DocumentCodec.decode(DocumentCodec.encode(doc));
    expect(back.name, 'Part');
    final a = back.find('a') as ShapeNode;
    expect([a.width, a.depth, a.height, a.placement.rz, a.color], [40, 30, 5, 45, 0xFF112233]);
    final g = back.find('g') as GroupNode;
    expect(g.op, GroupOp.intersect);
    expect((back.find('c') as ShapeNode).isHole, isTrue);
    expect(back.roots.map((n) => n.geometryKey), doc.roots.map((n) => n.geometryKey));
  });

  group('rejects bad input with FormatException', () {
    for (final (label, text) in [
      ('not json', '{oops'),
      ('wrong app', '{"app":"Other","version":1,"nodes":[]}'),
      ('future version', '{"app":"EmpuCAD","version":99,"nodes":[]}'),
      ('no nodes', '{"app":"EmpuCAD","version":1}'),
      ('bad kind', '{"app":"EmpuCAD","version":1,"nodes":[{"type":"shape","kind":"torus","id":"x","size":[1,1,1],"at":[0,0,0],"rot":[0,0,0]}]}'),
      ('zero size', '{"app":"EmpuCAD","version":1,"nodes":[{"type":"shape","kind":"box","id":"x","size":[0,1,1],"at":[0,0,0],"rot":[0,0,0]}]}'),
      ('short vector', '{"app":"EmpuCAD","version":1,"nodes":[{"type":"shape","kind":"box","id":"x","size":[1,1,1],"at":[0,0],"rot":[0,0,0]}]}'),
    ]) {
      test(label, () => expect(() => DocumentCodec.decode(text), throwsA(isA<FormatException>())));
    }
  });

  test('absurdly deep nesting is refused rather than overflowing the stack', () {
    Map<String, Object?> nest(int d) => {'type': 'group', 'id': 'g$d', 'at': [0, 0, 0], 'rot': [0, 0, 0], 'children': d == 0 ? [] : [nest(d - 1)]};
    final text = jsonEncode({'app': 'EmpuCAD', 'version': 1, 'nodes': [nest(200)]});
    expect(() => DocumentCodec.decode(text), throwsA(isA<FormatException>()));
  });
}
