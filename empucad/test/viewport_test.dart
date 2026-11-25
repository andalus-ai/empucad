import 'package:empucad/application/footprint.dart';
import 'package:empucad/application/mesh_shading.dart';
import 'package:empucad/application/picking.dart';
import 'package:empucad/application/scene_evaluator.dart';
import 'package:empucad/core/math/vec3.dart';
import 'package:empucad/domain/entities/document.dart';
import 'package:empucad/domain/entities/placement.dart';
import 'package:empucad/domain/entities/scene_node.dart';
import 'package:empucad/presentation/viewport/orbit_camera.dart';
import 'package:test/test.dart';

import 'support/fake_geometry_engine.dart';

ShapeNode box(String id, double x, {double z = 0}) =>
    ShapeNode(id: id, name: id, kind: ShapeKind.box, width: 10, depth: 10, height: 10, placement: Placement(x: x, z: z));

void main() {
  projectionAndShadingTests();
  test('camera looks at its target and the centre pixel ray passes through it', () {
    const cam = OrbitCamera(target: Vec3(5, 6, 7), distance: 100);
    final ray = cam.rayFor(400, 300, 800, 600);
    final t = (cam.target - ray.origin).dot(ray.direction);
    final closest = ray.at(t);
    expect((closest - cam.target).length, lessThan(1e-9));
    expect(t, closeTo(100, 1e-9));
  });

  test('elevation is clamped so the camera never flips over the pole', () {
    final c = const OrbitCamera().orbit(0, 500);
    expect(c.elevationDeg, 89);
    expect(c.right.length, closeTo(1, 1e-9));
  });

  test('pan moves the target in the screen plane only', () {
    const cam = OrbitCamera();
    final p = cam.pan(100, 0, 600);
    expect((p.target - cam.target).dot(cam.forward), closeTo(0, 1e-9));
    expect((p.target - cam.target).length, greaterThan(0));
  });

  test('picking returns the nearest box under the cursor, null on empty space', () async {
    final engine = FakeGeometryEngine();
    final ev = SceneEvaluator(engine);
    // two boxes along the camera's line of sight; "near" is closer to the eye
    final doc = Document(roots: [box('far', 0), box('near', 0, z: 0)]);
    final items = (await ev.evaluate(doc)).items;
    const cam = OrbitCamera(target: Vec3(0, 0, 5), distance: 100, azimuthDeg: 0, elevationDeg: 0);
    final hit = Picker.pick(cam.rayFor(400, 300, 800, 600), items);
    expect(hit, isNotNull);
    expect(hit!.distance, closeTo(95, 1e-3)); // eye at x=100, front face at x=5
    expect(Picker.pick(cam.rayFor(5, 5, 800, 600), items), isNull);
  });

  test('picking picks the closer of two separated boxes', () async {
    final ev = SceneEvaluator(FakeGeometryEngine());
    final doc = Document(roots: [box('a', 0), box('b', -40)]);
    final items = (await ev.evaluate(doc)).items;
    // camera on +X looking at -X: box a (x=0) is in front of box b (x=-40)
    const cam = OrbitCamera(target: Vec3(0, 0, 5), distance: 100, azimuthDeg: 0, elevationDeg: 0);
    expect(Picker.pick(cam.rayFor(400, 300, 800, 600), items)!.nodeId, 'a');
  });

  test('footprint: one outline per solid shape, holes skipped, group transform applied', () {
    final g = GroupNode(id: 'g', name: 'g', placement: const Placement(x: 100), children: [
      box('k', 0),
      ShapeNode(id: 'h', name: 'h', kind: ShapeKind.box, width: 2, depth: 2, height: 2, isHole: true),
    ]);
    final shapes = Footprint.of(Document(roots: [box('a', 0), g]));
    expect(shapes, hasLength(2));
    final xs = [for (var i = 0; i < 8; i += 2) shapes[1].outlines.single.points[i]];
    expect(xs.reduce((a, b) => a < b ? a : b), closeTo(95, 1e-9));
    expect(xs.reduce((a, b) => a > b ? a : b), closeTo(105, 1e-9));
  });

  test('footprint of round shapes is a 64-gon of the right radius', () {
    final d = Document(roots: [ShapeNode.round(id: 'c', name: 'c', kind: ShapeKind.cylinder, diameter: 20, height: 5)]);
    final pts = Footprint.of(d).single.outlines.single.points;
    expect(pts.length, 128);
    expect(pts[0], closeTo(10, 1e-9));
  });

  test('footprint can be restricted to selected shapes', () {
    final d = Document(roots: [box('a', 0), box('b', 50)]);
    expect(Footprint.of(d, only: {'b'}), hasLength(1));
  });
}

void projectionAndShadingTests() {
  test('project() is the inverse of rayFor()', () {
    const cam = OrbitCamera(target: Vec3(10, -5, 3), distance: 140, azimuthDeg: 30, elevationDeg: 25);
    for (final (px, py) in [(100.0, 80.0), (400.0, 300.0), (700.0, 550.0)]) {
      final p = cam.rayFor(px, py, 800, 600).at(77);
      final s = cam.project(p, 800, 600)!;
      expect(s.x, closeTo(px, 1e-6));
      expect(s.y, closeTo(py, 1e-6));
    }
  });

  test('points behind the camera do not project', () {
    const cam = OrbitCamera(target: Vec3.zero, distance: 100, azimuthDeg: 0, elevationDeg: 0);
    expect(cam.project(cam.eye + (cam.forward * -10), 800, 600), isNull);
  });

  test('flat shading: 3 unshared vertices per triangle with the face normal', () async {
    final cube = await FakeGeometryEngine().primitive(ShapeKind.box, width: 2, depth: 2, height: 2);
    final f = MeshShading.flat(cube);
    expect(f.vertexCount, cube.indices.length);
    for (var t = 0; t < f.vertexCount; t += 3) {
      // all three vertices of a triangle share one unit normal
      for (var k = 1; k < 3; k++) {
        for (var c = 0; c < 3; c++) {
          expect(f.normals[(t + k) * 3 + c], closeTo(f.normals[t * 3 + c], 1e-6));
        }
      }
      final n = Vec3(f.normals[t * 3], f.normals[t * 3 + 1], f.normals[t * 3 + 2]);
      expect(n.length, closeTo(1, 1e-6));
    }
  });

  test('every cube face normal points outward', () async {
    final cube = await FakeGeometryEngine().primitive(ShapeKind.box, width: 2, depth: 2, height: 2);
    final f = MeshShading.flat(cube);
    for (var t = 0; t < f.vertexCount; t += 3) {
      final centre = Vec3(
        (f.positions[t * 3] + f.positions[(t + 1) * 3] + f.positions[(t + 2) * 3]) / 3,
        (f.positions[t * 3 + 1] + f.positions[(t + 1) * 3 + 1] + f.positions[(t + 2) * 3 + 1]) / 3,
        (f.positions[t * 3 + 2] + f.positions[(t + 1) * 3 + 2] + f.positions[(t + 2) * 3 + 2]) / 3,
      );
      final n = Vec3(f.normals[t * 3], f.normals[t * 3 + 1], f.normals[t * 3 + 2]);
      expect(centre.dot(n), greaterThan(0), reason: 'triangle at $t faces inward');
    }
  });

  test('scene bounds cover all items; empty scene has none', () async {
    final ev = SceneEvaluator(FakeGeometryEngine());
    final r = await ev.evaluate(Document(roots: [box('a', 0), box('b', 30)]));
    final (lo, hi) = SceneBounds.of(r.items)!;
    expect([lo.x, hi.x], [-5, 35]);
    expect(SceneBounds.of(const []), isNull);
  });
}
