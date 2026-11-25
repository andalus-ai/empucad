import 'dart:math' as math;

/// 4x4 matrix, column-major (`m[col * 4 + row]`), Z-up, millimetres.
/// Immutable; build with the factories and compose with `*`.
final class Mat4 {
  Mat4._(List<double> m) : m = List.unmodifiable(m);
  final List<double> m;

  static final Mat4 identity = Mat4._([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  factory Mat4.translation(double x, double y, double z) => Mat4._([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]);

  factory Mat4.rotationX(double deg) {
    final (s, c) = _sc(deg);
    return Mat4._([1, 0, 0, 0, 0, c, s, 0, 0, -s, c, 0, 0, 0, 0, 1]);
  }

  factory Mat4.rotationY(double deg) {
    final (s, c) = _sc(deg);
    return Mat4._([c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1]);
  }

  factory Mat4.rotationZ(double deg) {
    final (s, c) = _sc(deg);
    return Mat4._([c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  }

  static (double, double) _sc(double deg) {
    final r = deg * math.pi / 180;
    return (math.sin(r), math.cos(r));
  }

  /// `this * o` (apply `o` first, then `this`).
  Mat4 operator *(Mat4 o) {
    final r = List<double>.filled(16, 0);
    for (var c = 0; c < 4; c++) {
      for (var row = 0; row < 4; row++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += m[k * 4 + row] * o.m[c * 4 + k];
        }
        r[c * 4 + row] = s;
      }
    }
    return Mat4._(r);
  }

  /// 3x4 column-major affine, the layout the Rust engine's `transform_mesh` expects.
  List<double> toAffine12() => [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10], m[12], m[13], m[14]];

  ({double x, double y, double z}) transformPoint(double x, double y, double z) => (
        x: m[0] * x + m[4] * y + m[8] * z + m[12],
        y: m[1] * x + m[5] * y + m[9] * z + m[13],
        z: m[2] * x + m[6] * y + m[10] * z + m[14],
      );

  @override
  bool operator ==(Object other) {
    if (other is! Mat4) return false;
    for (var i = 0; i < 16; i++) {
      if (m[i] != other.m[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(m);
}
