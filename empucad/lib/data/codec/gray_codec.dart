import 'dart:convert';
import 'dart:typed_data';

/// Compact text form for 8-bit grayscale pixels: run-length encoded, then base64.
///
/// Each run is two bytes: `count - 1` (so a run is 1..256 pixels) and the pixel value. Engraving
/// artwork has large flat areas, so this is far smaller than raw base64; the worst case (noise) is
/// 2x raw. Pure Dart, so it works on every platform including web.
abstract final class GrayCodec {
  static String encode(Uint8List gray) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < gray.length) {
      final v = gray[i];
      var run = 1;
      while (i + run < gray.length && gray[i + run] == v && run < 256) {
        run++;
      }
      out
        ..addByte(run - 1)
        ..addByte(v);
      i += run;
    }
    return base64Encode(out.takeBytes());
  }

  /// Throws [FormatException] unless the data decodes to exactly [expectedLength] pixels.
  static Uint8List decode(String text, int expectedLength) {
    final Uint8List packed;
    try {
      packed = base64Decode(text);
    } on FormatException {
      throw const FormatException('Image data is not valid base64');
    }
    if (packed.length.isOdd) throw const FormatException('Image data is truncated');
    final out = Uint8List(expectedLength);
    var n = 0;
    for (var i = 0; i < packed.length; i += 2) {
      final run = packed[i] + 1;
      if (n + run > expectedLength) throw const FormatException('Image data is longer than its declared size');
      out.fillRange(n, n + run, packed[i + 1]);
      n += run;
    }
    if (n != expectedLength) throw FormatException('Image data has $n pixels, expected $expectedLength');
    return out;
  }
}
