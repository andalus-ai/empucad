import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Top-down 2D view of a toolpath preview buffer (x, y, z, rapid per move). Cuts are blue, rapids grey.
class ToolpathPreview extends StatelessWidget {
  const ToolpathPreview({super.key, required this.moves});
  final Float32List moves;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFF14171B), border: Border.all(color: Colors.white24)),
          child: ClipRect(child: CustomPaint(painter: _PathPainter(moves))),
        ),
      );
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.m);
  final Float32List m;

  @override
  void paint(Canvas canvas, Size size) {
    final n = m.length ~/ 4;
    if (n < 2) return;
    var lo = const Offset(double.infinity, double.infinity), hi = const Offset(-double.infinity, -double.infinity);
    for (var i = 0; i < n; i++) {
      final x = m[i * 4].toDouble(), y = m[i * 4 + 1].toDouble();
      lo = Offset(x < lo.dx ? x : lo.dx, y < lo.dy ? y : lo.dy);
      hi = Offset(x > hi.dx ? x : hi.dx, y > hi.dy ? y : hi.dy);
    }
    final span = (hi - lo);
    final scale = 0.9 * size.shortestSide / (span.dx > span.dy ? span.dx : span.dy).clamp(1e-6, double.infinity);
    Offset map(int i) => Offset(
          (m[i * 4] - lo.dx) * scale + (size.width - span.dx * scale) / 2,
          size.height - ((m[i * 4 + 1] - lo.dy) * scale + (size.height - span.dy * scale) / 2), // Y up
        );
    final cut = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..strokeWidth = 1.2;
    final rapid = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 0.6;
    for (var i = 1; i < n; i++) {
      canvas.drawLine(map(i - 1), map(i), m[i * 4 + 3] == 1 ? rapid : cut);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => !identical(old.m, m);
}
