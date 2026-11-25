import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../application/mesh_shading.dart';
import '../../domain/ports/geometry_engine.dart' as domain;
import 'scene_renderer.dart';

/// GPU renderer on `flutter_scene` (Flutter GPU / Impeller). Requires Flutter >= 3.47 and
/// `--enable-flutter-gpu` on native platforms; see the README.
final class FlutterSceneRenderer implements SceneRenderer {
  const FlutterSceneRenderer();
  @override
  Widget build(BuildContext context, SceneRenderData data) => _SceneHost(data: data);
}

class _SceneHost extends StatefulWidget {
  const _SceneHost({required this.data});
  final SceneRenderData data;
  @override
  State<_SceneHost> createState() => _SceneHostState();
}

class _Entry {
  _Entry(this.node, this.material);
  final Node node;
  final PhysicallyBasedMaterial material;
}

class _SceneHostState extends State<_SceneHost> {
  final Scene _scene = Scene();
  // Keyed by MeshData identity: the evaluator hands back the same instance for unchanged parts,
  // so unchanged geometry is never re-uploaded.
  final Map<domain.MeshData, _Entry> _entries = {};
  Node? _workplane;
  bool _ready = false;

  // CAD is Z-up; flutter_scene is Y-up. Rotating -90 degrees about X maps (x, y, z) -> (x, z, -y).
  static final vm.Matrix4 _zUpToYUp = vm.Matrix4.rotationX(-math.pi / 2);
  static vm.Vector3 _toScene(double x, double y, double z) => vm.Vector3(x, z, -y);

  @override
  void initState() {
    super.initState();
    // Geometry and materials need the engine's static resources first.
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      _workplane = Node(
        name: 'workplane',
        mesh: Mesh(CuboidGeometry(vm.Vector3(400, 400, 0.4)), PhysicallyBasedMaterial()..setBaseColor(const Color(0xFF2B2F36))),
      )..localTransform = _zUpToYUp * vm.Matrix4.translation(vm.Vector3(150, 150, -0.2));
      _scene.add(_workplane!);
      setState(() => _ready = true);
      _sync();
    });
  }

  @override
  void didUpdateWidget(_SceneHost old) {
    super.didUpdateWidget(old);
    if (_ready) _sync();
  }

  void _sync() {
    final data = widget.data;
    final live = <domain.MeshData>{};
    for (final item in data.items) {
      live.add(item.mesh);
      final e = _entries.putIfAbsent(item.mesh, () => _create(item.mesh));
      final argb = data.colorOf(item.nodeId);
      final color = Color(argb).withValues(alpha: item.isHole ? 0.35 : 1.0);
      e.material.setBaseColor(color);
      e.node.highlightColor = data.selected.contains(item.nodeId) ? vm.Vector4(1.0, 0.45, 0.0, 1.0) : null;
    }
    for (final gone in _entries.keys.where((m) => !live.contains(m)).toList()) {
      _scene.remove(_entries.remove(gone)!.node);
    }
  }

  _Entry _create(domain.MeshData m) {
    final flat = MeshShading.flat(m);
    final material = PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.65;
    final node = Node(mesh: Mesh(MeshGeometry.fromArrays(positions: flat.positions, normals: flat.normals), material))
      ..localTransform = _zUpToYUp;
    _scene.add(node);
    return _Entry(node, material);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    final c = widget.data.camera;
    final eye = c.eye, t = c.target;
    return SceneView(
      _scene,
      camera: PerspectiveCamera(
        fovRadiansY: c.fovDeg * math.pi / 180,
        position: _toScene(eye.x, eye.y, eye.z),
        target: _toScene(t.x, t.y, t.z),
        up: vm.Vector3(0, 1, 0),
        fovNear: math.max(0.1, c.distance / 500),
        fovFar: c.distance * 50,
      ),
    );
  }
}
