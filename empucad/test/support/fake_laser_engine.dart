import 'dart:typed_data';

import 'package:empucad/domain/laser/laser_models.dart';
import 'package:empucad/domain/ports/laser_engine.dart';

/// Records what it was asked to plan and returns a canned result.
final class FakeLaserEngine implements LaserEngine {
  List<LaserShapeInput>? lastShapes;
  List<LaserLayerSettings>? lastLayers;
  LaserMachine? lastMachine;
  RasterImage? lastImage;
  RasterSettings? lastRaster;
  List<String> warnings = const [];

  LaserResult get _result => LaserResult(gcode: 'M2', seconds: 12, preview: Float32List(0), warnings: warnings);

  @override
  Future<LaserResult> planLayers(List<LaserShapeInput> shapes, List<LaserLayerSettings> layers, LaserMachine machine) async {
    lastShapes = shapes;
    lastLayers = layers;
    lastMachine = machine;
    return _result;
  }

  @override
  Future<LaserResult> planRaster(RasterImage image, RasterSettings settings, LaserMachine machine) async {
    lastImage = image;
    lastRaster = settings;
    lastMachine = machine;
    return _result;
  }
}
