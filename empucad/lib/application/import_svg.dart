import '../domain/entities/scene_node.dart';
import '../domain/ports/geometry_engine.dart';
import '../domain/ports/svg_importer.dart';

/// SVG text -> one extruded [OutlineNode]. Throws [InvalidInputFailure] when the file has no shapes.
final class ImportSvg {
  const ImportSvg(this._importer);
  final SvgImporter _importer;

  Future<OutlineNode> call(String svg, {required String id, String name = 'SVG', double height = 3.0, double toleranceMm = 0.05}) async {
    final r = await _importer.importSvg(svg, toleranceMm: toleranceMm);
    if (r.shapes.isEmpty) throw const InvalidInputFailure('The SVG contains no paths to import.');
    return OutlineNode(id: id, name: name, shapes: r.shapes, height: height);
  }
}
