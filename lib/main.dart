import 'package:empucad_engine/empucad_engine.dart' as engine;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/storage/file_selector_export_service.dart';
import 'presentation/state/export_service.dart';
import 'presentation/viewport/canvas_scene_renderer.dart';
import 'presentation/viewport/viewport.dart';

/// `flutter run --enable-flutter-gpu` uses the GPU renderer (default).
/// `flutter run --dart-define=EMPUCAD_RENDERER=canvas` uses the software fallback.
const _renderer = String.fromEnvironment('EMPUCAD_RENDERER', defaultValue: 'gpu');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await engine.RustLib.init(); // loads the Rust library built by the plugin
  const files = FileSelectorExportService();
  runApp(ProviderScope(
    overrides: [
      exportServiceProvider.overrideWithValue(files),
      importServiceProvider.overrideWithValue(files),
      if (_renderer == 'canvas') sceneRendererProvider.overrideWithValue(const CanvasSceneRenderer()),
    ],
    child: const EmpuCadApp(),
  ));
}
