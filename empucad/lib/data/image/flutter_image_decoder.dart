import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../application/grayscale.dart';
import '../../domain/laser/laser_models.dart';
import '../../domain/ports/image_decoder.dart';

/// Decodes any format Flutter can (PNG, JPEG, GIF, WebP, BMP) and converts it to grayscale.
/// The codec downsamples while decoding, so a 40-megapixel photo never sits in memory at full size.
final class FlutterImageDecoder implements ImageDecoder {
  const FlutterImageDecoder();

  @override
  Future<RasterImage> decode(Uint8List bytes, {int maxSide = 2000}) async {
    final probe = await ui.instantiateImageCodec(bytes);
    final first = await probe.getNextFrame();
    final (w, h) = (first.image.width, first.image.height);
    first.image.dispose();
    probe.dispose();

    final scale = maxSide / (w > h ? w : h);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: scale < 1 ? (w * scale).round().clamp(1, maxSide) : null,
    );
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw const FormatException('The image could not be decoded.');
        return Grayscale.fromRgba(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
