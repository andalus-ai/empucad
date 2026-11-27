import '../domain/entities/document.dart';
import '../domain/laser/laser_models.dart';
import '../domain/ports/laser_engine.dart';

export '../domain/ports/laser_engine.dart' show LaserFailure;
import 'laser_job_builder.dart';

/// Plans vector layers for the whole design or a selection.
final class GenerateLaserJob {
  const GenerateLaserJob(this._engine);
  final LaserEngine _engine;

  Future<LaserResult> call(Document doc, {Set<String>? only}) async {
    final plan = LaserJobBuilder.build(doc, only: only);
    if (plan.isEmpty) {
      throw const LaserFailure('Nothing to burn: add a shape, or enable the layer it is assigned to.');
    }
    final r = await _engine.planLayers(plan.shapes, plan.layers, plan.machine);
    return LaserResult(gcode: r.gcode, seconds: r.seconds, preview: r.preview, warnings: [...plan.warnings, ...r.warnings]);
  }
}

/// Plans an image burn, checking the image fits on the bed first.
final class GenerateRasterJob {
  const GenerateRasterJob(this._engine);
  final LaserEngine _engine;

  /// Height of the burned image in mm for a given width, from the image's aspect ratio.
  static double heightFor(RasterImage image, double widthMm) => widthMm * image.height / image.width;

  Future<LaserResult> call(RasterImage image, RasterSettings s, LaserMachine m) async {
    if (s.widthMm <= 0 || s.interval <= 0 || s.speed <= 0) {
      throw const LaserFailure('Width, line interval and speed must be positive.');
    }
    if (s.powerMax <= 0 || s.powerMin < 0 || s.powerMin > s.powerMax || s.powerMax > 100) {
      throw const LaserFailure('Power must satisfy 0 <= min <= max <= 100.');
    }
    final h = heightFor(image, s.widthMm);
    final warnings = [
      if (s.x < 0 || s.y < 0 || s.x + s.widthMm > m.bedWidth + 1e-6 || s.y + h > m.bedHeight + 1e-6)
        'The image extends outside the ${m.bedWidth.round()} x ${m.bedHeight.round()} mm bed.',
    ];
    final r = await _engine.planRaster(image, s, m);
    return LaserResult(gcode: r.gcode, seconds: r.seconds, preview: r.preview, warnings: [...warnings, ...r.warnings]);
  }
}
