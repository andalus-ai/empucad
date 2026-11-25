import 'dart:math' as math;

/// Minimal immutable 3D vector. Pure Dart so geometry logic stays testable off-device.
final class Vec3 {
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  final double x, y, z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));
  Vec3 normalized() {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }

  @override
  bool operator ==(Object other) => other is Vec3 && other.x == x && other.y == y && other.z == z;
  @override
  int get hashCode => Object.hash(x, y, z);
  @override
  String toString() => 'Vec3($x, $y, $z)';
}

/// A ray with a unit direction.
final class Ray {
  Ray(this.origin, Vec3 direction) : direction = direction.normalized();
  final Vec3 origin;
  final Vec3 direction;
  Vec3 at(double t) => origin + direction * t;
}
