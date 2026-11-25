import 'package:empucad_engine/empucad_engine.dart' as rust;

import '../../domain/laser/laser_models.dart';
import '../../domain/ports/laser_engine.dart';
import 'outline_mapping.dart';

/// [LaserEngine] backed by the Rust planner. Coordinates are machine coordinates (Y up) in and out;
/// the Rust bridge owns the conversion to the planner's internal space.
final class RustLaserEngine implements LaserEngine {
  const RustLaserEngine();

  @override
  Future<LaserResult> planLayers(List<LaserShapeInput> shapes, List<LaserLayerSettings> layers, LaserMachine machine) => _guard(() async {
        final r = await rust.planLaser(
          shapes: [for (final s in shapes) rust.LaserShapeSpec(layer: s.layer, outlines: [for (final o in s.outlines) OutlineMapping.toRust(o)])],
          layers: [for (final l in layers) _layer(l)],
          machine: _machine(machine),
        );
        return LaserResult(gcode: r.gcode, seconds: r.seconds, preview: await rust.previewLaserGcode(gcode: r.gcode));
      });

  @override
  Future<LaserResult> planRaster(RasterImage image, RasterSettings s, LaserMachine machine) => _guard(() async {
        final r = await rust.planRasterJob(
          gray: image.gray,
          width: image.width,
          height: image.height,
          spec: rust.RasterSpec(
            x: s.x,
            y: s.y,
            widthMm: s.widthMm,
            interval: s.interval,
            speed: s.speed,
            powerMin: s.powerMin,
            powerMax: s.powerMax,
            bidirectional: s.bidirectional,
            overscan: s.overscan,
            invert: s.invert,
            mode: s.mode == RasterMode.dither ? rust.RasterModeSpec.dither : rust.RasterModeSpec.grayscale,
          ),
          machine: _machine(machine),
        );
        return LaserResult(gcode: r.gcode, seconds: r.seconds, preview: await rust.previewLaserGcode(gcode: r.gcode));
      });

  static rust.LaserMachineSpec _machine(LaserMachine m) =>
      rust.LaserMachineSpec(bedW: m.bedWidth, bedH: m.bedHeight, sMax: m.sMax, rapid: m.rapid, dynamicPower: m.dynamicPower);

  static rust.LaserLayerSpec _layer(LaserLayerSettings l) => rust.LaserLayerSpec(
        index: l.index,
        mode: l.mode == LaserLayerMode.fill ? rust.LayerModeSpec.fill : rust.LayerModeSpec.line,
        speed: l.speed,
        power: l.power,
        passes: l.passes,
        interval: l.interval,
        angle: l.angle,
        bidirectional: l.bidirectional,
        overscan: l.overscan,
      );

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on rust.EngineApiError catch (e) {
      throw LaserFailure(e.detail);
    }
  }
}
