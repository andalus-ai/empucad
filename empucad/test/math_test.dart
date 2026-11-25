import 'package:empucad/core/math/mat4.dart';
import 'package:test/test.dart';

void main() {
  test('rotationZ(90) sends +X to +Y', () {
    final p = Mat4.rotationZ(90).transformPoint(1, 0, 0);
    expect(p.x, closeTo(0, 1e-12));
    expect(p.y, closeTo(1, 1e-12));
  });

  test('multiplication applies the right operand first', () {
    final m = Mat4.translation(10, 0, 0) * Mat4.rotationZ(90);
    final p = m.transformPoint(1, 0, 0); // rotate to (0,1,0) then translate
    expect(p.x, closeTo(10, 1e-12));
    expect(p.y, closeTo(1, 1e-12));
  });

  test('toAffine12 is column-major 3x4 with translation last', () {
    final a = Mat4.translation(1, 2, 3).toAffine12();
    expect(a, [1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 2, 3]);
    final r = Mat4.rotationZ(90).toAffine12();
    expect(r[0], closeTo(0, 1e-12)); // x basis = (0,1,0)
    expect(r[1], closeTo(1, 1e-12));
    expect(r[3], closeTo(-1, 1e-12)); // y basis = (-1,0,0)
  });
}
