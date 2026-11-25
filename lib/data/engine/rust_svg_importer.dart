import 'package:empucad_engine/empucad_engine.dart' as rust;

import '../../domain/ports/geometry_engine.dart';
import '../../domain/ports/svg_importer.dart';
import 'outline_mapping.dart';

/// [SvgImporter] backed by the Rust engine (`usvg` parsing, curves flattened to `toleranceMm`).
final class RustSvgImporter implements SvgImporter {
  const RustSvgImporter();

  @override
  Future<SvgImportResult> importSvg(String svg, {double toleranceMm = 0.05}) async {
    try {
      final r = await rust.importSvgShapes(svg: svg, toleranceMm: toleranceMm);
      return SvgImportResult(shapes: [for (final s in r.shapes) OutlineMapping.shapeFromRust(s)], widthMm: r.widthMm, heightMm: r.heightMm);
    } on rust.EngineApiError catch (e) {
      throw InvalidInputFailure(e.detail);
    }
  }
}
