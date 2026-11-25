import 'package:flutter/widgets.dart';

import '../../application/scene_evaluator.dart';
import 'orbit_camera.dart';

/// Everything a renderer needs to draw one frame. Renderers draw; they never pick, edit or
/// evaluate, so swapping the implementation cannot change behaviour.
final class SceneRenderData {
  const SceneRenderData({required this.items, required this.colorOf, required this.selected, required this.camera});
  final List<RenderItem> items;

  /// 0xAARRGGBB for a node id.
  final int Function(String nodeId) colorOf;
  final Set<String> selected;
  final OrbitCamera camera;
}

/// Port for 3D drawing. Implementations: `FlutterSceneRenderer` (GPU) and `CanvasSceneRenderer`
/// (software fallback for stable-channel development and widget tests).
abstract interface class SceneRenderer {
  Widget build(BuildContext context, SceneRenderData data);
}
