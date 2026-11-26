import 'dart:typed_data';

import '../entities/outline.dart';

export '../entities/outline.dart';

enum CamOperationKind { profileOutside, profileInside, profileOn, pocket, engrave, drill }

final class CamOperation {
  const CamOperation({
    required this.name,
    required this.kind,
    required this.shapes,
    this.toolNumber = 1,
    this.toolDiameter = 3.0,
    this.depth = 3.0,
    this.stepDown = 1.0,
    this.stepOver = 0.45,
    this.climb = true,
    this.feed = 800,
    this.plunge = 300,
    this.rpm = 12000,
    this.tabCount = 0,
    this.tabWidth = 6.0,
    this.tabHeight = 1.0,
    this.rampLength = 0.0,
  });
  final String name;
  final CamOperationKind kind;
  final List<ShapeOutlines> shapes;
  final int toolNumber;
  final double toolDiameter, depth, stepDown, stepOver, feed, plunge, rpm;

  /// Holding tabs (profiles only); 0 = none. Width is along the tool-centre path.
  final int tabCount;
  final double tabWidth, tabHeight;

  /// Descend along the path over this length instead of plunging; 0 = plunge.
  final double rampLength;
  final bool climb;

  CamOperation copyWith({
    CamOperationKind? kind,
    List<ShapeOutlines>? shapes,
    double? toolDiameter,
    double? depth,
    double? stepDown,
    int? tabCount,
    double? tabWidth,
    double? tabHeight,
    double? rampLength,
  }) =>
      CamOperation(
        name: name,
        kind: kind ?? this.kind,
        shapes: shapes ?? this.shapes,
        toolNumber: toolNumber,
        toolDiameter: toolDiameter ?? this.toolDiameter,
        depth: depth ?? this.depth,
        stepDown: stepDown ?? this.stepDown,
        stepOver: stepOver,
        climb: climb,
        feed: feed,
        plunge: plunge,
        rpm: rpm,
        tabCount: tabCount ?? this.tabCount,
        tabWidth: tabWidth ?? this.tabWidth,
        tabHeight: tabHeight ?? this.tabHeight,
        rampLength: rampLength ?? this.rampLength,
      );
}

final class CamSettings {
  const CamSettings({this.postId = 'grbl', this.inches = false, this.safeZ = 5, this.clearZ = 1, this.rapidRate = 3000, this.arcs = false});
  final String postId;
  final bool inches;
  final double safeZ, clearZ, rapidRate;

  /// Emit G2/G3 arcs where cuts lie on a circle: smaller, smoother programs. Off by default because
  /// a few older controllers handle arcs poorly.
  final bool arcs;

  CamSettings copyWith({String? postId, bool? inches, bool? arcs}) =>
      CamSettings(postId: postId ?? this.postId, inches: inches ?? this.inches, safeZ: safeZ, clearZ: clearZ, rapidRate: rapidRate, arcs: arcs ?? this.arcs);
}

final class PostInfo {
  const PostInfo({required this.id, required this.name, required this.extension});
  final String id, name, extension;
}

final class CamResult {
  const CamResult({required this.gcode, required this.fileExtension, required this.seconds, required this.preview});
  final String gcode, fileExtension;
  final double seconds;

  /// x, y, z, rapid(1|0) per move, in mm.
  final Float32List preview;
}

final class CamFailure implements Exception {
  const CamFailure(this.message);
  final String message;
  @override
  String toString() => 'CamFailure: $message';
}

/// Toolpath + G-code port. The Rust adapter lives in `data/`.
abstract interface class CamEngine {
  Future<List<PostInfo>> posts();
  Future<CamResult> generate(List<CamOperation> operations, CamSettings settings);
}
