import 'dart:typed_data';

import '../entities/outline.dart';

enum LaserLayerMode { line, fill }

/// One burn layer: how fast and how hard to burn the shapes assigned to it.
final class LaserLayerSettings {
  const LaserLayerSettings({
    required this.index,
    required this.name,
    required this.color,
    this.mode = LaserLayerMode.line,
    this.speed = 10,
    this.power = 50,
    this.passes = 1,
    this.interval = 0.1,
    this.angle = 0,
    this.bidirectional = true,
    this.overscan = 2.5,
    this.enabled = true,
  });

  final int index;
  final String name;

  /// 0xAARRGGBB swatch shown in the UI.
  final int color;
  final LaserLayerMode mode;

  /// mm/s
  final double speed;

  /// percent of the machine's S range
  final double power;
  final int passes;

  /// Fill line spacing, mm.
  final double interval;

  /// Fill scan angle, degrees.
  final double angle;
  final bool bidirectional;
  final double overscan;
  final bool enabled;

  LaserLayerSettings copyWith({
    String? name,
    LaserLayerMode? mode,
    double? speed,
    double? power,
    int? passes,
    double? interval,
    double? angle,
    bool? bidirectional,
    double? overscan,
    bool? enabled,
  }) =>
      LaserLayerSettings(
        index: index,
        name: name ?? this.name,
        color: color,
        mode: mode ?? this.mode,
        speed: speed ?? this.speed,
        power: power ?? this.power,
        passes: passes ?? this.passes,
        interval: interval ?? this.interval,
        angle: angle ?? this.angle,
        bidirectional: bidirectional ?? this.bidirectional,
        overscan: overscan ?? this.overscan,
        enabled: enabled ?? this.enabled,
      );
}

final class LaserMachine {
  const LaserMachine({this.bedWidth = 400, this.bedHeight = 400, this.sMax = 1000, this.rapid = 6000, this.dynamicPower = true});
  final double bedWidth, bedHeight, sMax, rapid;

  /// true = `M4` (power follows speed, best for engraving); false = `M3` constant power.
  final bool dynamicPower;

  LaserMachine copyWith({double? bedWidth, double? bedHeight, double? sMax, double? rapid, bool? dynamicPower}) => LaserMachine(
        bedWidth: bedWidth ?? this.bedWidth,
        bedHeight: bedHeight ?? this.bedHeight,
        sMax: sMax ?? this.sMax,
        rapid: rapid ?? this.rapid,
        dynamicPower: dynamicPower ?? this.dynamicPower,
      );
}

/// Machine, layers and which design node burns on which layer. Lives in the [Document].
final class LaserSetup {
  const LaserSetup({this.machine = const LaserMachine(), this.layers = defaultLayers, this.layerOf = const {}, this.raster});

  static const defaultLayers = <LaserLayerSettings>[
    LaserLayerSettings(index: 0, name: 'Cut', color: 0xFFEF4444, speed: 6, power: 90),
    LaserLayerSettings(index: 1, name: 'Score', color: 0xFF3B82F6, speed: 30, power: 25),
    LaserLayerSettings(index: 2, name: 'Engrave', color: 0xFF22C55E, mode: LaserLayerMode.fill, speed: 120, power: 30),
    LaserLayerSettings(index: 3, name: 'Mark', color: 0xFFEAB308, speed: 60, power: 15),
    LaserLayerSettings(index: 4, name: 'Fill 2', color: 0xFFA855F7, mode: LaserLayerMode.fill, speed: 80, power: 40),
  ];

  final LaserMachine machine;
  final List<LaserLayerSettings> layers;

  /// Node id -> layer index. A node without an entry burns on layer 0 (or its nearest group's layer).
  final Map<String, int> layerOf;

  /// The image to engrave, if one is loaded.
  final RasterAsset? raster;

  LaserSetup copyWith({LaserMachine? machine, List<LaserLayerSettings>? layers, Map<String, int>? layerOf, RasterAsset? raster, bool clearRaster = false}) =>
      LaserSetup(
        machine: machine ?? this.machine,
        layers: layers ?? this.layers,
        layerOf: layerOf ?? this.layerOf,
        raster: clearRaster ? null : (raster ?? this.raster),
      );

  LaserLayerSettings? layer(int index) {
    for (final l in layers) {
      if (l.index == index) return l;
    }
    return null;
  }
}

/// One design shape's outlines on a layer, in machine coordinates (mm, origin bottom-left, Y up).
final class LaserShapeInput {
  const LaserShapeInput({required this.layer, required this.outlines});
  final int layer;
  final List<Outline> outlines;
}

/// 8-bit grayscale, row-major, top row first, 0 = black.
final class RasterImage {
  RasterImage({required this.width, required this.height, required this.gray}) {
    if (width <= 0 || height <= 0 || gray.length != width * height) {
      throw ArgumentError('RasterImage ${width}x$height needs ${width * height} pixels, got ${gray.length}');
    }
  }
  final int width, height;
  final Uint8List gray;
}

enum RasterMode { grayscale, dither }

final class RasterSettings {
  const RasterSettings({
    this.x = 0,
    this.y = 0,
    this.widthMm = 50,
    this.interval = 0.1,
    this.speed = 150,
    this.powerMin = 5,
    this.powerMax = 60,
    this.bidirectional = true,
    this.overscan = 3,
    this.invert = false,
    this.mode = RasterMode.grayscale,
  });

  /// Bottom-left corner of the image on the bed, mm (machine coordinates, Y up).
  final double x, y;

  /// Height follows from the image's aspect ratio.
  final double widthMm, interval, speed, powerMin, powerMax, overscan;
  final bool bidirectional, invert;
  final RasterMode mode;

  RasterSettings copyWith({
    double? x,
    double? y,
    double? widthMm,
    double? interval,
    double? speed,
    double? powerMin,
    double? powerMax,
    bool? bidirectional,
    double? overscan,
    bool? invert,
    RasterMode? mode,
  }) =>
      RasterSettings(
        x: x ?? this.x,
        y: y ?? this.y,
        widthMm: widthMm ?? this.widthMm,
        interval: interval ?? this.interval,
        speed: speed ?? this.speed,
        powerMin: powerMin ?? this.powerMin,
        powerMax: powerMax ?? this.powerMax,
        bidirectional: bidirectional ?? this.bidirectional,
        overscan: overscan ?? this.overscan,
        invert: invert ?? this.invert,
        mode: mode ?? this.mode,
      );
}

/// The image to engrave, with how to burn it. Lives in the [LaserSetup] so it is saved with the design.
final class RasterAsset {
  const RasterAsset({required this.name, required this.image, required this.settings});
  final String name;
  final RasterImage image;
  final RasterSettings settings;

  RasterAsset withSettings(RasterSettings s) => RasterAsset(name: name, image: image, settings: s);
}

/// What the engine returns for a laser job.
final class LaserResult {
  const LaserResult({required this.gcode, required this.seconds, required this.preview, this.warnings = const []});
  final String gcode;
  final double seconds;

  /// x, y, power(S), rapid(1|0) per move, in machine mm.
  final Float32List preview;
  final List<String> warnings;
}
