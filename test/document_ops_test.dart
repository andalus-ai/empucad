import 'package:empucad/application/document_ops.dart';
import 'package:empucad/application/history.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:test/test.dart';

ShapeNode box(String id, {double x = 0, double y = 0}) =>
    ShapeNode(id: id, name: id, kind: ShapeKind.box, width: 10, depth: 10, height: 10, placement: Placement(x: x, y: y));

void main() {
  final base = Document(roots: [box('a'), box('b', x: 20), box('c', x: 40)]);

  test('group collects selected roots where the first one was, keeping order of the rest', () {
    final d = DocumentOps.group(base, {'a', 'c'}, groupId: 'g');
    expect(d.roots.map((n) => n.id), ['g', 'b']);
    expect((d.roots.first as GroupNode).children.map((n) => n.id), ['a', 'c']);
  });

  test('grouping fewer than two nodes is a no-op', () {
    expect(identical(DocumentOps.group(base, {'a'}, groupId: 'g'), base), isTrue);
  });

  test('ungroup bakes a Z-rotated group into its children', () {
    final g = GroupNode(id: 'g', name: 'g', children: [box('k', x: 10)], placement: const Placement(x: 5, y: 0, rz: 90));
    final d = DocumentOps.ungroup(Document(roots: [g]), 'g');
    final k = d.roots.single;
    expect(k.placement.x, closeTo(5, 1e-9)); // (10,0) rotated 90deg -> (0,10), plus group offset (5,0)
    expect(k.placement.y, closeTo(10, 1e-9));
    expect(k.placement.rz, 90);
  });

  test('ungroup refuses a group tilted about X (cannot be expressed) instead of corrupting it', () {
    final g = GroupNode(id: 'g', name: 'g', children: [box('k')], placement: const Placement(rx: 30));
    final doc = Document(roots: [g]);
    expect(identical(DocumentOps.ungroup(doc, 'g'), doc), isTrue);
  });

  test('toggleHole and move reach into nested groups', () {
    final g = GroupNode(id: 'g', name: 'g', children: [box('k')]);
    var d = Document(roots: [g]);
    d = DocumentOps.toggleHole(d, {'k'});
    d = DocumentOps.move(d, 'k', dx: 3, dz: 2);
    final k = d.find('k')!;
    expect(k.isHole, isTrue);
    expect([k.placement.x, k.placement.z], [3, 2]);
  });

  test('remove deletes nested nodes', () {
    final g = GroupNode(id: 'g', name: 'g', children: [box('k'), box('m')]);
    final d = DocumentOps.remove(Document(roots: [g]), {'k'});
    expect(d.allNodes.map((n) => n.id), ['g', 'm']);
  });

  test('history undo/redo, redo cleared by a new edit, limit respected', () {
    final h = History<int>(0, limit: 3);
    for (final v in [1, 2, 3, 4]) {
      h.push(v);
    }
    expect(h.present, 4);
    h.undo();
    h.undo();
    h.undo();
    expect(h.present, 1); // limit 3: the oldest state (0) was dropped
    expect(h.canUndo, isFalse);
    h.redo();
    expect(h.present, 2);
    h.push(9);
    expect(h.canRedo, isFalse);
  });
}
