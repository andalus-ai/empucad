import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/mesh_shading.dart';
import '../../application/scene_evaluator.dart';
import '../../core/math/vec3.dart';
import '../viewport/orbit_camera.dart';
import 'editor_notifier.dart';
import 'engine_providers.dart';

/// The evaluated scene. Re-runs when the document changes; the evaluator's cache keeps unchanged
/// parts instant, and Riverpod drops stale results if edits arrive faster than booleans finish.
final sceneProvider = FutureProvider<EvaluationResult>((ref) {
  final doc = ref.watch(documentProvider);
  return ref.watch(evaluatorProvider).evaluate(doc);
});

class CameraNotifier extends Notifier<OrbitCamera> {
  @override
  OrbitCamera build() => const OrbitCamera(target: Vec3(20, 20, 10), distance: 220);

  void orbit(double dAz, double dEl) => state = state.orbit(dAz, dEl);
  void zoom(double factor) => state = state.zoom(factor);
  void pan(double dx, double dy, double viewportHeight) => state = state.pan(dx, dy, viewportHeight);

  void frameScene(EvaluationResult? scene) {
    final b = scene == null ? null : SceneBounds.of(scene.items);
    if (b != null) state = state.frame(b.$1, b.$2);
  }
}

final cameraProvider = NotifierProvider<CameraNotifier, OrbitCamera>(CameraNotifier.new);

/// When true, a one-finger / left-button drag pans instead of orbiting (desktop has no 2nd finger).
class PanModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
}

final panModeProvider = NotifierProvider<PanModeNotifier, bool>(PanModeNotifier.new);
