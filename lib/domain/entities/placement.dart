import '../../core/math/mat4.dart';

/// Where a node sits. `z` is the bottom of the shape (it rests on the workplane at z = 0).
/// Rotations are degrees, applied X then Y then Z.
final class Placement {
  const Placement({this.x = 0, this.y = 0, this.z = 0, this.rx = 0, this.ry = 0, this.rz = 0});
  static const origin = Placement();
  final double x, y, z, rx, ry, rz;

  Placement copyWith({double? x, double? y, double? z, double? rx, double? ry, double? rz}) =>
      Placement(x: x ?? this.x, y: y ?? this.y, z: z ?? this.z, rx: rx ?? this.rx, ry: ry ?? this.ry, rz: rz ?? this.rz);

  Mat4 toMatrix() => Mat4.translation(x, y, z) * Mat4.rotationZ(rz) * Mat4.rotationY(ry) * Mat4.rotationX(rx);

  String get key => '$x,$y,$z,$rx,$ry,$rz';

  @override
  bool operator ==(Object other) => other is Placement && other.key == key;
  @override
  int get hashCode => key.hashCode;
}
