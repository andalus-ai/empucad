import 'dart:math' as math;

import 'package:empucad/core/math/mat4.dart';
import 'package:test/test.dart';

Mat4 compose(double tx, double ty, double tz, double rx, double ry, double rz, double sx, double sy, double sz) =>
    Mat4.translation(tx, ty, tz) * Mat4.rotationZ(rz) * Mat4.rotationY(ry) * Mat4.rotationX(rx) * Mat4.scaling(sx, sy, sz);

void expectSame(Mat4 a, Mat4 b, {double eps = 1e-9}) {
  for (var i = 0; i < 16; i++) {
    expect(a.m[i], closeTo(b.m[i], eps), reason: 'element $i');
  }
}

Mat4 rebuild(Decomposed d) => compose(d.tx, d.ty, d.tz, d.rxDeg, d.ryDeg, d.rzDeg, d.sx, d.sy, d.sz);

void main() {
  test('decompose then recompose gives back the same matrix over many random transforms', () {
    final rnd = math.Random(42);
    double r(double lo, double hi) => lo + rnd.nextDouble() * (hi - lo);
    for (var i = 0; i < 500; i++) {
      final m = compose(r(-50, 50), r(-50, 50), r(-50, 50), r(-180, 180), r(-89, 89), r(-180, 180), r(0.1, 5), r(0.1, 5), r(0.1, 5));
      final d = m.decompose();
      expect(d.sheared, isFalse);
      expect(d.mirrored, isFalse);
      expectSame(rebuild(d), m, eps: 1e-8);
    }
  });

  test('reads back plain translation, scale and a single-axis rotation exactly', () {
    final d = compose(1, 2, 3, 0, 0, 90, 2, 3, 4).decompose();
    expect([d.tx, d.ty, d.tz], [1, 2, 3]);
    expect([d.sx, d.sy, d.sz].map((v) => (v * 1e6).round() / 1e6), [2, 3, 4]);
    expect([d.rxDeg, d.ryDeg].map((v) => v.abs() < 1e-9), [true, true]);
    expect(d.rzDeg, closeTo(90, 1e-9));
  });

  test('gimbal lock (Y rotated exactly +/-90 degrees) still reproduces the matrix', () {
    for (final ry in [90.0, -90.0]) {
      for (final (rx, rz) in [(0.0, 0.0), (30.0, 0.0), (0.0, 45.0), (20.0, 70.0)]) {
        final m = compose(5, 6, 7, rx, ry, rz, 1.5, 2.5, 3.5);
        expectSame(rebuild(m.decompose()), m, eps: 1e-7);
      }
    }
  });

  test('a mirror is folded into local X and flagged; the result is a proper rotation', () {
    final m = compose(0, 0, 0, 10, 20, 30, 1, 1, 1) * Mat4.scaling(-1, 1, 1);
    final d = m.decompose();
    expect(d.mirrored, isTrue);
    expect(d.sheared, isFalse);
    // the rebuilt (proper) matrix is m with the mirror undone: m * diag(-1, 1, 1). For a shape that is
    // symmetric about its local X axis (box, cylinder, sphere, cone) the geometry is identical.
    expectSame(rebuild(d), m * Mat4.scaling(-1, 1, 1), eps: 1e-9);
    final p = rebuild(d).transformPoint(0, 7, 9), q = m.transformPoint(0, 7, 9);
    expect(p.x, closeTo(q.x, 1e-9), reason: 'points on the mirror plane (local x = 0) do not move');
    expect(p.y, closeTo(q.y, 1e-9));
    expect(p.z, closeTo(q.z, 1e-9));
  });

  test('non-orthogonal columns (a rotation followed by non-uniform scale) are flagged as sheared', () {
    final m = Mat4.scaling(2, 1, 1) * Mat4.rotationZ(30);
    expect(m.decompose().sheared, isTrue);
    expect(Mat4.rotationZ(30).decompose().sheared, isFalse);
  });

  test('fromColumnMajor validates its input', () {
    expect(() => Mat4.fromColumnMajor([1, 2, 3]), throwsA(isA<ArgumentError>()));
    expect(() => Mat4.fromColumnMajor(List.filled(16, double.nan)), throwsA(isA<ArgumentError>()));
    expectSame(Mat4.fromColumnMajor([...Mat4.identity.m]), Mat4.identity);
  });
}
