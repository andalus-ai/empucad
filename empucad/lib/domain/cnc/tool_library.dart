enum CncToolKind { endMill, ballNose, vBit, drill }

/// A cutter and the speeds that suit it. Feeds are mm/min, spindle speed is rpm.
final class CncTool {
  const CncTool({
    required this.id,
    required this.name,
    required this.kind,
    required this.diameter,
    required this.feed,
    required this.plunge,
    required this.rpm,
    this.angle = 0,
  });

  final String id;
  final String name;
  final CncToolKind kind;

  /// Cutting diameter in mm (for a V-bit, the widest cut).
  final double diameter;
  final double feed, plunge, rpm;

  /// Included angle in degrees. Only for V-bits.
  final double angle;

  bool get isV => kind == CncToolKind.vBit;

  CncTool copyWith({String? name, CncToolKind? kind, double? diameter, double? feed, double? plunge, double? rpm, double? angle}) => CncTool(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        diameter: diameter ?? this.diameter,
        feed: feed ?? this.feed,
        plunge: plunge ?? this.plunge,
        rpm: rpm ?? this.rpm,
        angle: angle ?? this.angle,
      );
}

/// The design's tools. The position in [tools] is the tool number sent to the controller (1-based).
final class ToolLibrary {
  const ToolLibrary([this.tools = defaults]);

  static const defaults = <CncTool>[
    CncTool(id: 't1', name: '3 mm flat end mill', kind: CncToolKind.endMill, diameter: 3, feed: 800, plunge: 300, rpm: 12000),
    CncTool(id: 't2', name: '6 mm flat end mill', kind: CncToolKind.endMill, diameter: 6, feed: 1000, plunge: 350, rpm: 10000),
    CncTool(id: 't3', name: '3 mm ball nose', kind: CncToolKind.ballNose, diameter: 3, feed: 700, plunge: 250, rpm: 12000),
    CncTool(id: 't4', name: '60° V-bit', kind: CncToolKind.vBit, diameter: 6.35, angle: 60, feed: 600, plunge: 250, rpm: 12000),
    CncTool(id: 't5', name: '90° V-bit', kind: CncToolKind.vBit, diameter: 6.35, angle: 90, feed: 600, plunge: 250, rpm: 12000),
    CncTool(id: 't6', name: '3 mm drill', kind: CncToolKind.drill, diameter: 3, feed: 200, plunge: 120, rpm: 10000),
  ];

  final List<CncTool> tools;

  CncTool? find(String id) {
    for (final t in tools) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 1-based controller tool number, or null if the tool is not in the library.
  int? numberOf(String id) {
    final i = tools.indexWhere((t) => t.id == id);
    return i < 0 ? null : i + 1;
  }

  ToolLibrary copyWith({List<CncTool>? tools}) => ToolLibrary(tools ?? this.tools);
}
