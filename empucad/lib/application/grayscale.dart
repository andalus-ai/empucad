import 'dart:typed_data';

import '../domain/laser/laser_models.dart';

/// RGBA -> 8-bit gray. Transparent pixels count as white (they burn nothing), partially transparent
/// ones are composited over white first. Uses Rec. 709 luma.
abstract final class Grayscale {
  static RasterImage fromRgba(Uint8List rgba, int width, int height) {
    if (rgba.length != width * height * 4) {
      throw ArgumentError('Expected ${width * height * 4} RGBA bytes for ${width}x$height, got ${rgba.length}');
    }
    final gray = Uint8List(width * height);
    for (var i = 0; i < gray.length; i++) {
      final a = rgba[i * 4 + 3] / 255.0;
      double over(int c) => c * a + 255 * (1 - a);
      final y = 0.2126 * over(rgba[i * 4]) + 0.7152 * over(rgba[i * 4 + 1]) + 0.0722 * over(rgba[i * 4 + 2]);
      gray[i] = y.round().clamp(0, 255);
    }
    return RasterImage(width: width, height: height, gray: gray);
  }
}
