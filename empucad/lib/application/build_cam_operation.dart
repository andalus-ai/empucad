import '../domain/cnc/tool_library.dart';
import '../domain/ports/cam_engine.dart';

/// Which tools may perform which operation. Used to filter the tool list in the UI and to refuse a
/// bad combination before anything reaches the engine.
abstract final class ToolCompat {
  static bool allows(CamOperationKind op, CncToolKind tool) => switch (op) {
        CamOperationKind.profileOutside || CamOperationKind.profileInside || CamOperationKind.profileOn || CamOperationKind.pocket =>
          tool == CncToolKind.endMill || tool == CncToolKind.ballNose,
        CamOperationKind.engrave => tool != CncToolKind.drill,
        CamOperationKind.drill => tool == CncToolKind.drill || tool == CncToolKind.endMill,
        CamOperationKind.vcarve => tool == CncToolKind.vBit,
      };

  /// The tool to use: [wanted] if it exists and suits [op], else the first library tool that does,
  /// else null (nothing in the library can do this operation).
  static CncTool? resolve(ToolLibrary lib, CamOperationKind op, String? wanted) {
    final chosen = wanted == null ? null : lib.find(wanted);
    if (chosen != null && allows(op, chosen.kind)) return chosen;
    for (final t in lib.tools) {
      if (allows(op, t.kind)) return t;
    }
    return null;
  }

  static String reason(CamOperationKind op, CncTool tool) => switch (op) {
        CamOperationKind.vcarve => 'V-carve needs a V-bit; "${tool.name}" is not one.',
        CamOperationKind.drill => 'Drilling needs a drill or a flat end mill; "${tool.name}" cannot plunge-drill.',
        CamOperationKind.engrave => 'A drill bit cannot engrave. Choose an end mill, ball nose or V-bit.',
        _ => 'Cutting out or pocketing needs a flat end mill or ball nose; "${tool.name}" cannot.',
      };
}

/// Combines the operation settings with the chosen tool's geometry and speeds.
/// Throws [CamFailure] with a readable message on a bad combination.
abstract final class BuildCamOperation {
  static CamOperation call({
    required CamOperationKind kind,
    required CncTool tool,
    required int toolNumber,
    required List<ShapeOutlines> shapes,
    double depth = 3,
    double stepDown = 1,
    double stepOver = 0.45,
    int tabCount = 0,
    double tabWidth = 6,
    double tabHeight = 1,
    double rampLength = 0,
  }) {
    if (!ToolCompat.allows(kind, tool.kind)) throw CamFailure(ToolCompat.reason(kind, tool));
    if (depth <= 0) throw const CamFailure('Depth must be greater than zero.');
    if (stepDown <= 0) throw const CamFailure('Depth per pass must be greater than zero.');
    final profile = kind == CamOperationKind.profileOutside || kind == CamOperationKind.profileInside || kind == CamOperationKind.profileOn;
    if (profile && tabCount > 0 && tabHeight >= depth) {
      throw CamFailure('Tabs ${_n(tabHeight)} mm high do not fit in a ${_n(depth)} mm deep cut: they would never be cut. Lower the tab height or cut deeper.');
    }
    return CamOperation(
      name: kind.name,
      kind: kind,
      shapes: shapes,
      toolNumber: toolNumber,
      toolDiameter: tool.diameter,
      toolAngle: tool.isV ? tool.angle : 0,
      depth: depth,
      stepDown: stepDown,
      stepOver: stepOver,
      feed: tool.feed,
      plunge: tool.plunge,
      rpm: tool.rpm,
      tabCount: profile ? tabCount : 0,
      tabWidth: tabWidth,
      tabHeight: tabHeight,
      rampLength: rampLength,
    );
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
