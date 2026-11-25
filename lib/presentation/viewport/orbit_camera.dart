import 'dart:math' as math;

import '../../core/math/vec3.dart';

/// Z-up orbit camera. Pure math: the renderer reads [eye]/[target]/[up]; picking uses [rayFor].
/// Immutable; every gesture returns a new camera, which keeps Riverpod state trivial.
final class OrbitCamera {
  const OrbitCamera({
    this.target = Vec3.zero,
    this.distance = 250,
    this.azimuthDeg = -45,
    this.elevationDeg = 30,
    this.fovDeg = 45,
  });

  final Vec3 target;
  final double distance, azimuthDeg, elevationDeg, fovDeg;

  static const _minElevation = -89.0, _maxElevation = 89.0;

  OrbitCamera orbit(double dAzimuthDeg, double dElevationDeg) => OrbitCamera(
        target: target,
        distance: distance,
        azimuthDeg: azimuthDeg + dAzimuthDeg,
        elevationDeg: (elevationDeg + dElevationDeg).clamp(_minElevation, _maxElevation),
        fovDeg: fovDeg,
      );

  OrbitCamera zoom(double factor) => OrbitCamera(
        target: target,
        distance: (distance * factor).clamp(1.0, 100000.0),
        azimuthDeg: azimuthDeg,
        elevationDeg: elevationDeg,
        fovDeg: fovDeg,
      );

  /// Pan in screen space by `dx`,`dy` pixels for a viewport of height `viewportHeight`.
  OrbitCamera pan(double dx, double dy, double viewportHeight) {
    final worldPerPixel = 2 * distance * math.tan(fovDeg * math.pi / 360) / viewportHeight;
    final delta = right * (-dx * worldPerPixel) + up * (dy * worldPerPixel);
    return OrbitCamera(target: target + delta, distance: distance, azimuthDeg: azimuthDeg, elevationDeg: elevationDeg, fovDeg: fovDeg);
  }

  /// Frame a bounding box: centre on it and back off far enough to see all of it.
  OrbitCamera frame(Vec3 lo, Vec3 hi) {
    final centre = (lo + hi) * 0.5;
    final radius = math.max((hi - lo).length / 2, 1.0);
    return OrbitCamera(
      target: centre,
      distance: radius / math.sin(fovDeg * math.pi / 360) * 1.1,
      azimuthDeg: azimuthDeg,
      elevationDeg: elevationDeg,
      fovDeg: fovDeg,
    );
  }

  /// Direction from the target towards the eye.
  Vec3 get _offsetDir {
    final az = azimuthDeg * math.pi / 180, el = elevationDeg * math.pi / 180;
    return Vec3(math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el));
  }

  Vec3 get eye => target + _offsetDir * distance;
  Vec3 get forward => (target - eye).normalized();
  Vec3 get right => forward.cross(const Vec3(0, 0, 1)).normalized();
  Vec3 get up => right.cross(forward).normalized();

  /// World-space ray through pixel (`px`,`py`) of a `width` x `height` viewport (origin top-left).
  Ray rayFor(double px, double py, double width, double height) {
    final ndcX = (2 * px / width - 1) * (width / height);
    final ndcY = 1 - 2 * py / height;
    final t = math.tan(fovDeg * math.pi / 360);
    final dir = forward + right * (ndcX * t) + up * (ndcY * t);
    return Ray(eye, dir);
  }

  /// Inverse of [rayFor]: pixel position and view depth of a world point, or null if it is behind
  /// the camera. Used by the canvas fallback renderer; consistent with picking by construction.
  ({double x, double y, double depth})? project(Vec3 p, double width, double height) {
    final v = p - eye;
    final depth = v.dot(forward);
    if (depth <= 0.01) return null;
    final t = math.tan(fovDeg * math.pi / 360);
    final ndcX = v.dot(right) / (depth * t) * (height / width);
    final ndcY = v.dot(up) / (depth * t);
    return (x: (ndcX + 1) * width / 2, y: (1 - ndcY) * height / 2, depth: depth);
  }
}
