import 'dart:typed_data';

import '../laser/laser_models.dart';

/// Decodes PNG/JPEG/etc. bytes to grayscale. Implemented with `dart:ui` in `data/`.
abstract interface class ImageDecoder {
  /// `maxSide` caps the longer side in pixels (the image is downscaled, never enlarged).
  Future<RasterImage> decode(Uint8List bytes, {int maxSide = 2000});
}
