import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Bed-shaped top view of laser moves (x, y, power, rapid per move). Burns are orange, stronger
/// power is more opaque; travel moves are faint grey. Y is up, like the machine.
class LaserPreview extends StatelessWidget {
  const LaserPreview({super.key, required this.moves, required this.bedWidth, required this.bedHeight, required this.sMax});
  final Float32List moves;
  final double bedWidth, bedHeight, sMax;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: bedWidth / bedHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xFF14171B), border: Border.all(color: Colors.white24)),
          child: ClipRect(child: CustomPaint(painter: _Painter(moves, bedWidth, bedHeight, sMax))),
        ),
      );
}

class _Painter extends CustomPainter {
  _Painter(this.m, this.bw, this.bh, this.sMax);
  final Float32List m;
  final double bw, bh, sMax;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / bw, sy = size.height / bh;
    Offset at(int i) => Offset(m[i * 4] * sx, size.height - m[i * 4 + 1] * sy);
    final travel = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 0.5;
    final burn = Paint()..strokeWidth = 1.2;
    for (var i = 1; i < m.length ~/ 4; i++) {
      final power = m[i * 4 + 2];
      if (m[i * 4 + 3] == 1 || power <= 0) {
        canvas.drawLine(at(i - 1), at(i), travel);
      } else {
        burn.color = const Color(0xFFFF8A00).withValues(alpha: (0.25 + 0.75 * (power / sMax)).clamp(0.25, 1.0));
        canvas.drawLine(at(i - 1), at(i), burn);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => !identical(old.m, m) || old.bw != bw || old.bh != bh || old.sMax != sMax;
}
