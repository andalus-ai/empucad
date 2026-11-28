import 'mesh_data.dart';
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

/// An imported mesh (e.g. from an STL file). The mesh is stored as imported, centred in X/Y with its base
/// at z = 0. The node scales it by ([sx], [sy], [sz]) about that origin, then places it with [placement],
/// so resizing never lifts it off the workplane.
final class MeshNode extends SceneNode {
  MeshNode({
    required super.id,
    required super.name,
    required this.mesh,
    required this.meshHash,
    required this.meshWidth,
    required this.meshDepth,
    required this.meshHeight,
    this.sx = 1,
    this.sy = 1,
    this.sz = 1,
    super.placement = Placement.origin,
    super.isHole = false,
    super.color = 0xFF94A3B8,
  });

  /// Computes the content fingerprint and size once; edits that only move or resize the node reuse them.
  factory MeshNode.fromMesh({
    required String id,
    required String name,
    required MeshData mesh,
    double sx = 1,
    double sy = 1,
    double sz = 1,
    Placement placement = Placement.origin,
    bool isHole = false,
    int color = 0xFF94A3B8,
  }) {
    var lo = [double.infinity, double.infinity, double.infinity], hi = [-double.infinity, -double.infinity, -double.infinity];
    final p = mesh.positions;
    for (var i = 0; i + 2 < p.length; i += 3) {
      for (var k = 0; k < 3; k++) {
        if (p[i + k] < lo[k]) lo[k] = p[i + k];
        if (p[i + k] > hi[k]) hi[k] = p[i + k];
      }
    }
    final empty = p.length < 3;
    return MeshNode(
      id: id, name: name, mesh: mesh, meshHash: hashMesh(mesh),
      meshWidth: empty ? 0 : hi[0] - lo[0], meshDepth: empty ? 0 : hi[1] - lo[1], meshHeight: empty ? 0 : hi[2] - lo[2],
      sx: sx, sy: sy, sz: sz, placement: placement, isHole: isHole, color: color,
    );
  }

  final MeshData mesh;

  /// Fingerprint of the mesh content, so identical meshes share a cache entry and edited ones do not.
  final int meshHash;

  /// Size of the mesh as imported, before scaling.
  final double meshWidth, meshDepth, meshHeight;

  /// Scale factors along the mesh's own X, Y and Z.
  final double sx, sy, sz;

  /// Size as it appears in the design.
  double get width => meshWidth * sx;
  double get depth => meshDepth * sy;
  double get height => meshHeight * sz;

  static int hashMesh(MeshData m) => Object.hash(m.positions.length, m.indices.length, Object.hashAll(m.positions), Object.hashAll(m.indices));

  /// Resize to the given dimensions in mm. With [keepAspect] the first dimension given decides one factor
  /// that is applied to all three axes; otherwise each given dimension scales only its own axis. An axis the
  /// mesh has no extent along (a perfectly flat mesh) cannot be scaled and is left alone.
  MeshNode resized({double? width, double? depth, double? height, bool keepAspect = false}) {
    double factor(double? target, double current) => target != null && target > 0 && target.isFinite && current > 1e-9 ? target / current : double.nan;
    final fx = factor(width, meshWidth), fy = factor(depth, meshDepth), fz = factor(height, meshHeight);
    if (keepAspect) {
      final f = [fx, fy, fz].firstWhere((v) => !v.isNaN, orElse: () => double.nan);
      if (f.isNaN) return this;
      return copyWith(sx: f, sy: f, sz: f);
    }
    return copyWith(sx: fx.isNaN ? sx : fx, sy: fy.isNaN ? sy : fy, sz: fz.isNaN ? sz : fz);
  }

  MeshNode copyWith({String? name, Placement? placement, bool? isHole, int? color, double? sx, double? sy, double? sz}) => MeshNode(
        id: id,
        name: name ?? this.name,
        mesh: mesh,
        meshHash: meshHash,
        meshWidth: meshWidth,
        meshDepth: meshDepth,
        meshHeight: meshHeight,
        sx: sx ?? this.sx,
        sy: sy ?? this.sy,
        sz: sz ?? this.sz,
        placement: placement ?? this.placement,
        isHole: isHole ?? this.isHole,
        color: color ?? this.color,
      );

  @override
  MeshNode withPlacement(Placement p) => copyWith(placement: p);
  @override
  MeshNode withName(String n) => copyWith(name: n);
  @override
  MeshNode withHole(bool h) => copyWith(isHole: h);
  @override
  MeshNode withColor(int c) => copyWith(color: c);

  @override
  String get geometryKey => 'M($meshHash,${mesh.triangleCount},$sx,$sy,$sz,${placement.key},$isHole)';
}
