import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/math/vec3.dart';
import 'orbit_camera.dart';
import 'scene_renderer.dart';

/// Software fallback: projects triangles with [OrbitCamera.project] and paints them back to front.
/// Needs no GPU features, so it runs on any Flutter channel and in widget tests. Sorting is per
/// triangle (painter's algorithm), so it suits small and medium scenes; use `FlutterSceneRenderer`
/// for real work.
final class CanvasSceneRenderer implements SceneRenderer {
  const CanvasSceneRenderer({this.maxTriangles = 60000});
  final int maxTriangles;

  @override
  Widget build(BuildContext context, SceneRenderData data) =>
      SizedBox.expand(child: CustomPaint(painter: _Painter(data, maxTriangles)));
}

class _Painter extends CustomPainter {
  _Painter(this.d, this.maxTriangles);
  final SceneRenderData d;
  final int maxTriangles;

  static const _light = Vec3(0.4, -0.5, 0.75);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B1E23));
    _grid(canvas, size);

    final tris = <_Tri>[];
    var budget = maxTriangles;
    for (final item in d.items) {
      final p = item.mesh.positions, idx = item.mesh.indices;
      final base = Color(d.colorOf(item.nodeId));
      final selected = d.selected.contains(item.nodeId);
      for (var i = 0; i + 2 < idx.length && budget > 0; i += 3, budget--) {
        final a = Vec3(p[idx[i] * 3], p[idx[i] * 3 + 1], p[idx[i] * 3 + 2]);
        final b = Vec3(p[idx[i + 1] * 3], p[idx[i + 1] * 3 + 1], p[idx[i + 1] * 3 + 2]);
        final c = Vec3(p[idx[i + 2] * 3], p[idx[i + 2] * 3 + 1], p[idx[i + 2] * 3 + 2]);
        final pa = d.camera.project(a, size.width, size.height);
        final pb = d.camera.project(b, size.width, size.height);
        final pc = d.camera.project(c, size.width, size.height);
        if (pa == null || pb == null || pc == null) continue;
        final n = (b - a).cross(c - a).normalized();
        final lit = 0.35 + 0.65 * math.max(0, n.dot(_light.normalized()));
        tris.add(_Tri(
          Offset(pa.x, pa.y), Offset(pb.x, pb.y), Offset(pc.x, pc.y),
          (pa.depth + pb.depth + pc.depth) / 3,
          _shade(base, lit, item.isHole ? 0.35 : 1.0),
          selected,
        ));
      }
    }
    tris.sort((x, y) => y.depth.compareTo(x.depth)); // far first

    final path = Path();
    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final t in tris) {
      path
        ..reset()
        ..moveTo(t.a.dx, t.a.dy)
        ..lineTo(t.b.dx, t.b.dy)
        ..lineTo(t.c.dx, t.c.dy)
        ..close();
      canvas.drawPath(path, fill..color = t.color);
      canvas.drawPath(path, edge..color = t.selected ? const Color(0xFFFF7300) : t.color);
    }
  }

  void _grid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2E333B)
      ..strokeWidth = 1;
    for (var i = -100; i <= 300; i += 20) {
      _line(canvas, size, Vec3(i.toDouble(), -100, 0), Vec3(i.toDouble(), 300, 0), paint);
      _line(canvas, size, Vec3(-100, i.toDouble(), 0), Vec3(300, i.toDouble(), 0), paint);
    }
  }

  void _line(Canvas canvas, Size size, Vec3 a, Vec3 b, Paint p) {
    final pa = d.camera.project(a, size.width, size.height), pb = d.camera.project(b, size.width, size.height);
    if (pa != null && pb != null) canvas.drawLine(Offset(pa.x, pa.y), Offset(pb.x, pb.y), p);
  }

  static Color _shade(Color c, double k, double alpha) =>
      Color.from(alpha: alpha, red: (c.r * k).clamp(0, 1), green: (c.g * k).clamp(0, 1), blue: (c.b * k).clamp(0, 1));

  @override
  bool shouldRepaint(_Painter old) => old.d != d;
}

class _Tri {
  _Tri(this.a, this.b, this.c, this.depth, this.color, this.selected);
  final Offset a, b, c;
  final double depth;
  final Color color;
  final bool selected;
}
