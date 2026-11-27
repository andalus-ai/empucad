import 'package:empucad/application/build_cam_operation.dart';
import 'package:empucad/application/document_ops.dart';
import 'package:empucad/data/codec/document_codec.dart';
import 'package:empucad/domain/cnc/tool_library.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/ports/cam_engine.dart';
import 'package:test/test.dart';

const flat = CncTool(id: 'a', name: 'flat', kind: CncToolKind.endMill, diameter: 3, feed: 900, plunge: 250, rpm: 15000);
const vbit = CncTool(id: 'v', name: 'V', kind: CncToolKind.vBit, diameter: 6, angle: 90, feed: 500, plunge: 200, rpm: 11000);
const drill = CncTool(id: 'd', name: 'drill', kind: CncToolKind.drill, diameter: 2, feed: 150, plunge: 100, rpm: 8000);
const shapes = <ShapeOutlines>[];

CamOperation build(CamOperationKind k, CncTool t, {double depth = 3, int tabs = 0, double tabHeight = 1}) =>
    BuildCamOperation.call(kind: k, tool: t, toolNumber: 2, shapes: shapes, depth: depth, tabCount: tabs, tabHeight: tabHeight);

String? failure(void Function() f) {
  try {
    f();
  } on CamFailure catch (e) {
    return e.message;
  }
  return null;
}

void main() {
  group('library', () {
    test('defaults cover every tool kind and tool numbers follow list position', () {
      const lib = ToolLibrary();
      expect(lib.tools.map((t) => t.kind).toSet(), CncToolKind.values.toSet());
      expect(lib.numberOf('t1'), 1);
      expect(lib.numberOf('t6'), 6);
      expect(lib.numberOf('nope'), isNull);
      expect(lib.find('t4')!.angle, 60);
    });

    test('add, update and remove; ids stay unique; the last tool cannot be removed', () {
      var d = const Document();
      d = DocumentOps.addTool(d, flat);
      expect(d.tools.tools.length, 7);
      expect(identical(DocumentOps.addTool(d, flat), d), isTrue, reason: 'duplicate id ignored');
      d = DocumentOps.updateTool(d, flat.copyWith(feed: 1234));
      expect(d.tools.find('a')!.feed, 1234);
      expect(d.tools.numberOf('a'), 7, reason: 'editing keeps the tool number');
      d = DocumentOps.removeTool(d, 'a');
      expect(d.tools.find('a'), isNull);
      var one = Document(tools: const ToolLibrary([flat]));
      one = DocumentOps.removeTool(one, 'a');
      expect(one.tools.tools, hasLength(1));
    });
  });

  group('codec', () {
    test('tools roundtrip', () {
      var d = DocumentOps.addTool(const Document(), vbit.copyWith(angle: 45));
      d = DocumentOps.updateTool(d, d.tools.find('t1')!.copyWith(rpm: 0, name: 'Spindle off'));
      final back = DocumentCodec.decode(DocumentCodec.encode(d)).tools;
      expect(back.tools.length, 7);
      expect(back.find('v')!.angle, 45);
      expect(back.find('t1')!.rpm, 0);
      expect(back.find('t1')!.name, 'Spindle off');
    });

    test('an older file with no tools opens with the default library', () {
      expect(DocumentCodec.decode('{"app":"EmpuCAD","version":1,"nodes":[]}').tools.tools, hasLength(6));
    });

    String doc(String tools) => '{"app":"EmpuCAD","version":1,"nodes":[],"tools":$tools}';
    const ok = '{"id":"a","kind":"endMill","diameter":3,"feed":800,"plunge":300,"rpm":12000}';
    for (final (label, tools) in [
      ('empty list', '[]'),
      ('duplicate id', '[$ok,$ok]'),
      ('unknown kind', '[{"id":"a","kind":"saw","diameter":3,"feed":1,"plunge":1,"rpm":1}]'),
      ('zero diameter', '[{"id":"a","kind":"endMill","diameter":0,"feed":1,"plunge":1,"rpm":1}]'),
      ('zero feed', '[{"id":"a","kind":"endMill","diameter":3,"feed":0,"plunge":1,"rpm":1}]'),
      ('negative rpm', '[{"id":"a","kind":"endMill","diameter":3,"feed":1,"plunge":1,"rpm":-5}]'),
      ('V-bit without angle', '[{"id":"a","kind":"vBit","diameter":3,"feed":1,"plunge":1,"rpm":1}]'),
      ('V-bit 180 degrees', '[{"id":"a","kind":"vBit","diameter":3,"angle":180,"feed":1,"plunge":1,"rpm":1}]'),
      ('not a list', '"x"'),
    ]) {
      test('rejects: $label', () => expect(() => DocumentCodec.decode(doc(tools)), throwsA(isA<FormatException>())));
    }

    test('zero rpm is allowed (a router with a fixed spindle)', () {
      expect(DocumentCodec.decode(doc('[{"id":"a","kind":"endMill","diameter":3,"feed":1,"plunge":1,"rpm":0}]')).tools.tools.single.rpm, 0);
    });
  });

  group('compatibility and building', () {
    test('the matrix: who may do what', () {
      bool ok(CamOperationKind o, CncTool t) => ToolCompat.allows(o, t.kind);
      expect(ok(CamOperationKind.vcarve, vbit), isTrue);
      expect(ok(CamOperationKind.vcarve, flat), isFalse);
      expect(ok(CamOperationKind.pocket, flat), isTrue);
      expect(ok(CamOperationKind.pocket, vbit), isFalse);
      expect(ok(CamOperationKind.profileOutside, drill), isFalse);
      expect(ok(CamOperationKind.drill, drill), isTrue);
      expect(ok(CamOperationKind.drill, flat), isTrue);
      expect(ok(CamOperationKind.drill, vbit), isFalse);
      expect(ok(CamOperationKind.engrave, vbit), isTrue);
      expect(ok(CamOperationKind.engrave, drill), isFalse);
    });

    test('resolve keeps a suitable choice, falls back when it does not suit or was deleted, and can find nothing', () {
      const lib = ToolLibrary();
      expect(ToolCompat.resolve(lib, CamOperationKind.pocket, 't2')!.id, 't2');
      expect(ToolCompat.resolve(lib, CamOperationKind.pocket, null)!.id, 't1', reason: 'first tool that suits');
      expect(ToolCompat.resolve(lib, CamOperationKind.pocket, 't4')!.id, 't1', reason: 'a V-bit cannot pocket');
      expect(ToolCompat.resolve(lib, CamOperationKind.vcarve, 't1')!.id, 't4', reason: 'switching to V-carve picks a V-bit');
      expect(ToolCompat.resolve(lib, CamOperationKind.drill, 'gone')!.id, 't1', reason: 'deleted tool id');
      expect(ToolCompat.resolve(const ToolLibrary([flat]), CamOperationKind.vcarve, null), isNull);
    });

    test('the operation takes diameter, angle, speeds and number from the tool', () {
      final op = build(CamOperationKind.vcarve, vbit);
      expect([op.toolDiameter, op.toolAngle, op.feed, op.plunge, op.rpm, op.toolNumber], [6, 90, 500, 200, 11000, 2]);
      final p = build(CamOperationKind.pocket, flat);
      expect([p.toolDiameter, p.toolAngle, p.feed, p.rpm], [3, 0, 900, 15000], reason: 'angle only for V-bits');
    });

    test('bad combinations fail with a message that names the tool', () {
      expect(failure(() => build(CamOperationKind.vcarve, flat)), contains('V-bit'));
      expect(failure(() => build(CamOperationKind.pocket, vbit)), contains('"V"'));
      expect(failure(() => build(CamOperationKind.engrave, drill)), contains('drill'));
    });

    test('tabs that cannot fit are refused for profiles, and ignored for other operations', () {
      expect(failure(() => build(CamOperationKind.profileOutside, flat, depth: 3, tabs: 4, tabHeight: 3)), contains('Tabs'));
      expect(failure(() => build(CamOperationKind.profileOutside, flat, depth: 3, tabs: 4, tabHeight: 1)), isNull);
      expect(failure(() => build(CamOperationKind.profileOutside, flat, depth: 3, tabs: 0, tabHeight: 9)), isNull, reason: 'no tabs, nothing to fit');
      expect(build(CamOperationKind.pocket, flat, tabs: 4).tabCount, 0, reason: 'tabs only apply to profiles');
    });

    test('dogbones are kept for inside profiles and pockets and dropped everywhere else', () {
      CamOperation op(CamOperationKind k, CncTool t) =>
          BuildCamOperation.call(kind: k, tool: t, toolNumber: 1, shapes: shapes, dogbones: true);
      expect(op(CamOperationKind.profileInside, flat).dogbones, isTrue);
      expect(op(CamOperationKind.pocket, flat).dogbones, isTrue);
      expect(op(CamOperationKind.profileOutside, flat).dogbones, isFalse);
      expect(op(CamOperationKind.profileOn, flat).dogbones, isFalse);
      expect(op(CamOperationKind.engrave, vbit).dogbones, isFalse);
      expect(op(CamOperationKind.vcarve, vbit).dogbones, isFalse);
      expect(op(CamOperationKind.drill, drill).dogbones, isFalse);
      expect(BuildCamOperation.call(kind: CamOperationKind.pocket, tool: flat, toolNumber: 1, shapes: shapes).dogbones, isFalse, reason: 'off by default');
    });

    test('non-positive depth or depth per pass is refused', () {
      expect(failure(() => build(CamOperationKind.pocket, flat, depth: 0)), contains('Depth'));
      expect(failure(() => BuildCamOperation.call(kind: CamOperationKind.pocket, tool: flat, toolNumber: 1, shapes: shapes, stepDown: 0)), contains('per pass'));
    });
  });
}
