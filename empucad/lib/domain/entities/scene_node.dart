import 'outline.dart';
import 'placement.dart';

enum ShapeKind { box, cylinder, sphere, cone }

/// How a group combines its solid children. Holes are always subtracted.
enum GroupOp { union, intersect, bundle }

/// A node in the design tree. Sealed so every `switch` over nodes is exhaustive.
sealed class SceneNode {
  const SceneNode({required this.id, required this.name, required this.placement, required this.isHole, required this.color});
  final String id;
  final String name;
  final Placement placement;
  final bool isHole;

  /// 0xAARRGGBB
  final int color;

  SceneNode withPlacement(Placement p);
  SceneNode withName(String n);
  SceneNode withHole(bool h);
  SceneNode withColor(int c);

  /// Identifies the geometry this node produces. Name and colour are excluded on purpose,
  /// so renaming or recolouring never triggers a boolean recompute.
  String get geometryKey;
}

final class ShapeNode extends SceneNode {
  const ShapeNode({
    required super.id,
    required super.name,
    required this.kind,
    required this.width,
    required this.depth,
    required this.height,
    super.placement = Placement.origin,
    super.isHole = false,
    super.color = 0xFF3B82F6,
  });

  final ShapeKind kind;

  /// Bounding size in mm. Cylinder/cone/sphere use `width` as the diameter and ignore `depth`
  /// (kept equal to `width` by [ShapeNode.round]).
  final double width, depth, height;

  factory ShapeNode.round({
    required String id,
    required String name,
    required ShapeKind kind,
    required double diameter,
    required double height,
    Placement placement = Placement.origin,
    bool isHole = false,
    int color = 0xFF3B82F6,
  }) =>
      ShapeNode(id: id, name: name, kind: kind, width: diameter, depth: diameter, height: height, placement: placement, isHole: isHole, color: color);

  ShapeNode copyWith({String? name, double? width, double? depth, double? height, Placement? placement, bool? isHole, int? color}) => ShapeNode(
        id: id,
        name: name ?? this.name,
        kind: kind,
        width: width ?? this.width,
        depth: depth ?? this.depth,
        height: height ?? this.height,
        placement: placement ?? this.placement,
        isHole: isHole ?? this.isHole,
        color: color ?? this.color,
      );

  @override
  ShapeNode withPlacement(Placement p) => copyWith(placement: p);
  @override
  ShapeNode withName(String n) => copyWith(name: n);
  @override
  ShapeNode withHole(bool h) => copyWith(isHole: h);
  @override
  ShapeNode withColor(int c) => copyWith(color: c);

  @override
  String get geometryKey => 'S(${kind.name},$width,$depth,$height,${placement.key},$isHole)';
}

final class GroupNode extends SceneNode {
  const GroupNode({
    required super.id,
    required super.name,
    required this.children,
    this.op = GroupOp.union,
    super.placement = Placement.origin,
    super.isHole = false,
    super.color = 0xFF9CA3AF,
  });

  final List<SceneNode> children;
  final GroupOp op;

  GroupNode copyWith({String? name, List<SceneNode>? children, GroupOp? op, Placement? placement, bool? isHole, int? color}) => GroupNode(
        id: id,
        name: name ?? this.name,
        children: children ?? this.children,
        op: op ?? this.op,
        placement: placement ?? this.placement,
        isHole: isHole ?? this.isHole,
        color: color ?? this.color,
      );

  @override
  GroupNode withPlacement(Placement p) => copyWith(placement: p);
  @override
  GroupNode withName(String n) => copyWith(name: n);
  @override
  GroupNode withHole(bool h) => copyWith(isHole: h);
  @override
  GroupNode withColor(int c) => copyWith(color: c);

  @override
  String get geometryKey => 'G(${op.name},${placement.key},$isHole,[${children.map((c) => c.geometryKey).join(';')}])';
}

/// Imported 2D geometry (e.g. from an SVG) extruded `height` mm up from its placement.
/// Each [ShapeOutlines] is one region; shapes are unioned into a single solid.
final class OutlineNode extends SceneNode {
  OutlineNode({
    required super.id,
    required super.name,
    required this.shapes,
    required this.height,
    super.placement = Placement.origin,
    super.isHole = false,
    super.color = 0xFFF59E0B,
  });

  final List<ShapeOutlines> shapes;
  final double height;

  // Cheap content fingerprint so identical outlines share a cache entry and edited ones do not.
  late final int _fingerprint = Object.hashAll([
    for (final s in shapes)
      for (final o in s.outlines) ...[o.closed, ...o.points],
  ]);

  OutlineNode copyWith({String? name, double? height, Placement? placement, bool? isHole, int? color}) => OutlineNode(
        id: id,
        name: name ?? this.name,
        shapes: shapes,
        height: height ?? this.height,
        placement: placement ?? this.placement,
        isHole: isHole ?? this.isHole,
        color: color ?? this.color,
      );

  @override
  OutlineNode withPlacement(Placement p) => copyWith(placement: p);
  @override
  OutlineNode withName(String n) => copyWith(name: n);
  @override
  OutlineNode withHole(bool h) => copyWith(isHole: h);
  @override
  OutlineNode withColor(int c) => copyWith(color: c);

  @override
  String get geometryKey => 'O($height,${placement.key},$isHole,$_fingerprint,${shapes.length})';
}
