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
  const LaserState({
    this.image,
    this.imageName,
    this.raster = const RasterSettings(),
    this.result = const AsyncData<LaserResult?>(null),
  });
  final RasterImage? image;
  final String? imageName;
  final RasterSettings raster;
  final AsyncValue<LaserResult?> result;

  LaserState copyWith({RasterImage? image, String? imageName, RasterSettings? raster, AsyncValue<LaserResult?>? result}) =>
      LaserState(image: image ?? this.image, imageName: imageName ?? this.imageName, raster: raster ?? this.raster, result: result ?? this.result);
}

/// Session state for the laser workspace. Layers, machine and layer assignments are NOT here: they
/// live in the document (saved, undoable). Only the loaded image and the last result are transient.
class LaserNotifier extends Notifier<LaserState> {
  @override
  LaserState build() => const LaserState();

  void setRaster(RasterSettings s) => state = state.copyWith(raster: s);

  Future<void> loadImage() async {
    try {
      final bytes = await ref.read(importServiceProvider).pickBytes(extensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']);
      if (bytes == null) return;
      final image = await ref.read(imageDecoderProvider).decode(bytes);
      state = state.copyWith(image: image, imageName: 'image ${image.width}x${image.height}', result: const AsyncData<LaserResult?>(null));
    } catch (e, st) {
      state = state.copyWith(result: AsyncError(const LaserFailure('That file could not be read as an image.'), st));
    }
  }

  Future<void> generateLayers() => _run(() {
        final doc = ref.read(documentProvider);
        final sel = ref.read(selectionProvider);
        return ref.read(generateLaserJobProvider)(doc, only: sel.isEmpty ? null : sel);
      });

  Future<void> generateImage() => _run(() {
        final image = state.image;
        if (image == null) throw const LaserFailure('Load an image first.');
        return ref.read(generateRasterJobProvider)(image, state.raster, ref.read(documentProvider).laser.machine);
      });

  Future<void> _run(Future<LaserResult> Function() job) async {
    state = state.copyWith(result: const AsyncLoading<LaserResult?>());
    state = state.copyWith(result: await AsyncValue.guard<LaserResult?>(job));
  }
}

final laserProvider = NotifierProvider<LaserNotifier, LaserState>(LaserNotifier.new);
