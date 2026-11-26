import 'dart:math' as math;

/// 4x4 matrix, column-major (`m[col * 4 + row]`), Z-up, millimetres.
/// Immutable; build with the factories and compose with `*`.
final class Mat4 {
  Mat4._(List<double> m) : m = List.unmodifiable(m);
  final List<double> m;

  static final Mat4 identity = Mat4._([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  /// From 16 numbers in column-major order (the layout three.js and most web CAD files use).
  factory Mat4.fromColumnMajor(List<double> m) {
    if (m.length != 16 || m.any((v) => !v.isFinite)) throw ArgumentError('A 4x4 matrix needs 16 finite numbers');
    return Mat4._(m);
  }

  factory Mat4.scaling(double sx, double sy, double sz) => Mat4._([sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, 0, 0, 0, 1]);

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

  /// Splits an affine matrix into `translate * Rz * Ry * Rx * scale` (the order [Placement] uses).
  ///
  /// Scales are the column lengths (always positive). If the matrix mirrors, the mirror is folded
  /// into the local X axis and [Decomposed.mirrored] is set: that is exact for shapes that are
  /// symmetric about X (box, cylinder, sphere, cone) but not for arbitrary groups. [Decomposed.sheared]
  /// is set when the columns are not orthogonal (non-uniform scale applied after a rotation), which
  /// this form cannot represent exactly.
  Decomposed decompose() {
    final sx = _len(0), sy = _len(4), sz = _len(8);
    final inv = [for (final s in [sx, sy, sz]) s < 1e-12 ? 0.0 : 1 / s];
    // rotation columns
    var r = [
      m[0] * inv[0], m[1] * inv[0], m[2] * inv[0],
      m[4] * inv[1], m[5] * inv[1], m[6] * inv[1],
      m[8] * inv[2], m[9] * inv[2], m[10] * inv[2],
    ];
    double dot(int a, int b) => r[a * 3] * r[b * 3] + r[a * 3 + 1] * r[b * 3 + 1] + r[a * 3 + 2] * r[b * 3 + 2];
    final sheared = dot(0, 1).abs() > 1e-4 || dot(0, 2).abs() > 1e-4 || dot(1, 2).abs() > 1e-4;
    final det = r[0] * (r[4] * r[8] - r[7] * r[5]) - r[3] * (r[1] * r[8] - r[7] * r[2]) + r[6] * (r[1] * r[5] - r[4] * r[2]);
    final mirrored = det < 0;
    if (mirrored) r = [-r[0], -r[1], -r[2], r[3], r[4], r[5], r[6], r[7], r[8]];
    // element (row i, col j) = r[j * 3 + i]
    final r00 = r[0], r10 = r[1], r20 = r[2], r11 = r[4], r21 = r[5], r12 = r[7], r22 = r[8];
    double rx, ry, rz;
    if (r20.abs() < 0.999999) {
      ry = math.asin(-r20);
      rx = math.atan2(r21, r22);
      rz = math.atan2(r10, r00);
    } else {
      ry = r20 < 0 ? math.pi / 2 : -math.pi / 2;
      rz = 0;
      rx = math.atan2(-r12, r11);
    }
    const deg = 180 / math.pi;
    return Decomposed(
      tx: m[12], ty: m[13], tz: m[14],
      sx: sx, sy: sy, sz: sz,
      rxDeg: rx * deg, ryDeg: ry * deg, rzDeg: rz * deg,
      mirrored: mirrored, sheared: sheared,
    );
  }

  double _len(int c) => math.sqrt(m[c] * m[c] + m[c + 1] * m[c + 1] + m[c + 2] * m[c + 2]);
}

final class Decomposed {
  const Decomposed({
    required this.tx, required this.ty, required this.tz,
    required this.sx, required this.sy, required this.sz,
    required this.rxDeg, required this.ryDeg, required this.rzDeg,
    required this.mirrored, required this.sheared,
  });
  final double tx, ty, tz, sx, sy, sz, rxDeg, ryDeg, rzDeg;
  final bool mirrored, sheared;
}
