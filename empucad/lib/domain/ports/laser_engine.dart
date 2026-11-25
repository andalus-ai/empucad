import '../laser/laser_models.dart';

/// The engine refused a laser job (bad settings, blank image, ...). Message is user-readable.
final class LaserFailure implements Exception {
  const LaserFailure(this.message);
  final String message;
  @override
  String toString() => 'LaserFailure: $message';
}

/// Laser planning port. The Rust adapter lives in `data/`.
abstract interface class LaserEngine {
  /// Plan vector layers. Shapes are in machine coordinates (origin bottom-left, Y up) and the G-code
  /// that comes back uses the same coordinates; any internal flip is the engine's business.
  Future<LaserResult> planLayers(List<LaserShapeInput> shapes, List<LaserLayerSettings> layers, LaserMachine machine);

  /// Plan an image burn. `settings.x/y` is the image's bottom-left corner in machine coordinates.
  Future<LaserResult> planRaster(RasterImage image, RasterSettings settings, LaserMachine machine);
}
