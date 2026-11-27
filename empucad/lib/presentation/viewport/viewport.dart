import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/laser_job_builder.dart';
import '../../application/picking.dart';
import '../state/editor_notifier.dart';
import '../state/scene_providers.dart';
import '../state/selection_notifier.dart';
import '../state/workspace_notifier.dart';
import 'flutter_scene_renderer.dart';
import 'scene_renderer.dart';

/// Which renderer draws the scene. `main.dart` overrides it with `CanvasSceneRenderer` when
/// started with `--dart-define=EMPUCAD_RENDERER=canvas`.
final sceneRendererProvider = Provider<SceneRenderer>((ref) => const FlutterSceneRenderer());

/// Hosts the renderer and turns gestures into camera moves and selection. Picking is CPU-side and
/// renderer-independent, so behaviour is identical whichever [SceneRenderer] is plugged in.
class Viewport extends ConsumerStatefulWidget {
  const Viewport({super.key});
  @override
  ConsumerState<Viewport> createState() => _ViewportState();
}

class _ViewportState extends ConsumerState<Viewport> {
  double _lastScale = 1;

  @override
  Widget build(BuildContext context) {
    final scene = ref.watch(sceneProvider);
    final camera = ref.watch(cameraProvider);
    final selection = ref.watch(selectionProvider);
    final doc = ref.watch(documentProvider);
    final renderer = ref.watch(sceneRendererProvider);
    final panMode = ref.watch(panModeProvider);
    // In the laser workspace shapes are coloured by the layer they burn on
    final laserView = ref.watch(workspaceProvider) == Workspace.laser;
    // Keep showing the previous frame while a boolean recomputes.
    final result = scene.value;
    final items = result?.items ?? const [];

    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final data = SceneRenderData(
        items: items,
        colorOf: (id) => (laserView ? LaserJobBuilder.viewColor(doc, id) : null) ?? doc.find(id)?.color ?? 0xFF9CA3AF,
        selected: selection,
        camera: camera,
      );
      final cam = ref.read(cameraProvider.notifier);
      return Stack(children: [
        Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) cam.zoom(e.scrollDelta.dy > 0 ? 1.1 : 1 / 1.1);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final ray = camera.rayFor(d.localPosition.dx, d.localPosition.dy, size.width, size.height);
              final hit = Picker.pick(ray, items);
              ref.read(selectionProvider.notifier).select(hit?.nodeId, additive: HardwareKeyboard.instance.isShiftPressed);
            },
            onScaleStart: (_) => _lastScale = 1,
            onScaleUpdate: (d) {
              if (d.pointerCount >= 2) {
                cam.pan(d.focalPointDelta.dx, d.focalPointDelta.dy, size.height);
                if (d.scale > 0) cam.zoom(_lastScale / d.scale);
                _lastScale = d.scale;
              } else if (panMode) {
                cam.pan(d.focalPointDelta.dx, d.focalPointDelta.dy, size.height);
              } else {
                cam.orbit(-d.focalPointDelta.dx * 0.5, d.focalPointDelta.dy * 0.5);
              }
            },
            child: renderer.build(context, data),
          ),
        ),
        if (scene.isLoading) const Positioned(top: 8, right: 8, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        if (result != null && result.warnings.isNotEmpty) Positioned(left: 8, bottom: 8, right: 8, child: _Banner(result.warnings.join('\n'))),
        if (scene.hasError) Positioned(left: 8, bottom: 8, right: 8, child: _Banner('Could not build the scene: ${scene.error}')),
      ]);
    });
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xCC7A2E00), borderRadius: BorderRadius.circular(6)),
        child: Padding(padding: const EdgeInsets.all(8), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))),
      );
}
