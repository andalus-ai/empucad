import 'package:empucad/domain/ports/cam_engine.dart';
import 'package:test/test.dart';

void main() {
  test('arcs are opt-in and copyWith changes only what it is told to', () {
    const s = CamSettings();
    expect(s.arcs, isFalse);
    final t = s.copyWith(arcs: true);
    expect(t.arcs, isTrue);
    expect([t.postId, t.inches, t.safeZ, t.clearZ, t.rapidRate], ['grbl', false, 5, 1, 3000]);
    expect(t.copyWith(postId: 'mach').arcs, isTrue, reason: 'unrelated edits keep the arc setting');
  });

  test('a V-carve operation defaults to a 60 degree bit and copyWith can change it', () {
    const op = CamOperation(name: 'v', kind: CamOperationKind.vcarve, shapes: []);
    expect(op.toolAngle, 60);
    expect(op.copyWith(toolAngle: 90).toolAngle, 90);
    expect(op.copyWith(depth: 2).toolAngle, 60);
  });
}
