import 'dart:typed_data';

import '../domain/entities/document.dart';
import '../domain/ports/geometry_engine.dart';
import 'scene_evaluator.dart';

/// Builds one STL for everything solid in the document (holes subtracted, parts unioned).
/// Returns null when there is nothing solid to export.
final class ExportStl {
  const ExportStl(this._evaluator, this._engine);
  final SceneEvaluator _evaluator;
  final GeometryEngine _engine;

  Future<Uint8List?> call(Document doc) async {
    final mesh = await _evaluator.combinedSolid(doc);
    return mesh == null ? null : _engine.encodeStl(mesh);
  }
}
