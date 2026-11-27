import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/generate_laser_job.dart';
import '../../data/engine/rust_laser_engine.dart';
import '../../data/image/flutter_image_decoder.dart';
import '../../domain/laser/laser_models.dart';
import '../../domain/ports/image_decoder.dart';
import '../../domain/ports/laser_engine.dart';
import 'editor_notifier.dart';
import 'export_service.dart';
import 'selection_notifier.dart';

final laserEngineProvider = Provider<LaserEngine>((ref) => const RustLaserEngine());
final imageDecoderProvider = Provider<ImageDecoder>((ref) => const FlutterImageDecoder());
final generateLaserJobProvider = Provider<GenerateLaserJob>((ref) => GenerateLaserJob(ref.watch(laserEngineProvider)));
final generateRasterJobProvider = Provider<GenerateRasterJob>((ref) => GenerateRasterJob(ref.watch(laserEngineProvider)));

final class LaserState {
  const LaserState({this.result = const AsyncData<LaserResult?>(null)});
  final AsyncValue<LaserResult?> result;
  LaserState copyWith({AsyncValue<LaserResult?>? result}) => LaserState(result: result ?? this.result);
}

/// Session state for the laser workspace: only the last generated job. Layers, machine, layer
/// assignments and the engraving image (with its settings) live in the document, so they are saved
/// and undoable.
class LaserNotifier extends Notifier<LaserState> {
  @override
  LaserState build() => const LaserState();

  void setRaster(RasterSettings s) => ref.read(editorProvider.notifier).updateRasterSettings(s);

  Future<void> loadImage() async {
    try {
      final bytes = await ref.read(importServiceProvider).pickBytes(extensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
      if (bytes == null) return;
      final image = await ref.read(imageDecoderProvider).decode(bytes);
      final previous = ref.read(documentProvider).laser.raster?.settings;
      ref.read(editorProvider.notifier).setRaster(RasterAsset(name: 'image ${image.width}x${image.height}', image: image, settings: previous ?? const RasterSettings()));
      state = state.copyWith(result: const AsyncData<LaserResult?>(null));
    } catch (e, st) {
      state = state.copyWith(result: AsyncError(const LaserFailure('That file could not be read as an image.'), st));
    }
  }

  void removeImage() {
    ref.read(editorProvider.notifier).clearRaster();
    state = state.copyWith(result: const AsyncData<LaserResult?>(null));
  }

  Future<void> generateLayers() => _run(() {
        final doc = ref.read(documentProvider);
        final sel = ref.read(selectionProvider);
        return ref.read(generateLaserJobProvider)(doc, only: sel.isEmpty ? null : sel);
      });

  Future<void> generateImage() => _run(() {
        final doc = ref.read(documentProvider);
        final asset = doc.laser.raster;
        if (asset == null) throw const LaserFailure('Load an image first.');
        return ref.read(generateRasterJobProvider)(asset.image, asset.settings, doc.laser.machine);
      });

  Future<void> _run(Future<LaserResult> Function() job) async {
    state = state.copyWith(result: const AsyncLoading<LaserResult?>());
    state = state.copyWith(result: await AsyncValue.guard<LaserResult?>(job));
  }
}

final laserProvider = NotifierProvider<LaserNotifier, LaserState>(LaserNotifier.new);
