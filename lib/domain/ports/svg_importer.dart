import '../entities/outline.dart';

final class SvgImportResult {
  const SvgImportResult({required this.shapes, required this.widthMm, required this.heightMm});
  final List<ShapeOutlines> shapes;
  final double widthMm, heightMm;
}

/// Parses SVG text into flat outlines in mm, Y up. The Rust adapter lives in `data/`.
abstract interface class SvgImporter {
  Future<SvgImportResult> importSvg(String svg, {double toleranceMm = 0.05});
}
