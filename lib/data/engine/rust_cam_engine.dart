import 'dart:typed_data';

import 'package:empucad_engine/empucad_engine.dart' as rust;

import '../../domain/ports/cam_engine.dart';

/// [CamEngine] backed by the Rust plugin: toolpaths from `empucad_core::cam`, G-code from its posts.
final class RustCamEngine implements CamEngine {
  const RustCamEngine();

  @override
  Future<List<PostInfo>> posts() async =>
      [for (final p in rust.listPosts()) PostInfo(id: p.id, name: p.name, extension: p.extension)];

  @override
  Future<CamResult> generate(List<CamOperation> operations, CamSettings s) async {
    try {
      final r = await rust.generateCam(
        job: rust.CamJobSpec(
          operations: [for (final o in operations) _op(o)],
          postId: s.postId,
          inches: s.inches,
          safeZ: s.safeZ,
          clearZ: s.clearZ,
          rapidRate: s.rapidRate,
        ),
      );
      return CamResult(gcode: r.gcode, fileExtension: r.fileExtension, seconds: r.seconds, preview: r.preview);
    } on rust.EngineApiError catch (e) {
      throw CamFailure(e.detail);
    }
  }

  static rust.OperationSpec _op(CamOperation o) => rust.OperationSpec(
        name: o.name,
        toolNumber: o.toolNumber,
        toolDiameter: o.toolDiameter,
        kind: switch (o.kind) {
          CamOperationKind.profileOutside => rust.ToolpathKind.profileOutside,
          CamOperationKind.profileInside => rust.ToolpathKind.profileInside,
          CamOperationKind.profileOn => rust.ToolpathKind.profileOn,
          CamOperationKind.pocket => rust.ToolpathKind.pocket,
          CamOperationKind.engrave => rust.ToolpathKind.engrave,
          CamOperationKind.drill => rust.ToolpathKind.drill,
        },
        shapes: [
          for (final s in o.shapes)
            rust.ShapeOutlines(outlines: [for (final l in s.outlines) rust.Outline(points: Float64List.fromList(l.points), closed: l.closed)]),
        ],
        depth: o.depth,
        stepDown: o.stepDown,
        stepOver: o.stepOver,
        climb: o.climb,
        feed: o.feed,
        plunge: o.plunge,
        rpm: o.rpm,
      );
}
