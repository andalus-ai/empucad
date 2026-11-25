import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/footprint.dart';
import '../../domain/ports/cam_engine.dart';
import 'editor_notifier.dart';
import 'engine_providers.dart';
import 'selection_notifier.dart';

final class CamState {
  const CamState({
    this.kind = CamOperationKind.profileOutside,
    this.toolDiameter = 3.0,
    this.depth = 3.0,
    this.stepDown = 1.0,
    this.settings = const CamSettings(),
    this.result = const AsyncData<CamResult?>(null),
  });
  final CamOperationKind kind;
  final double toolDiameter, depth, stepDown;
  final CamSettings settings;
  final AsyncValue<CamResult?> result;

  CamState copyWith({
    CamOperationKind? kind,
    double? toolDiameter,
    double? depth,
    double? stepDown,
    CamSettings? settings,
    AsyncValue<CamResult?>? result,
  }) =>
      CamState(
        kind: kind ?? this.kind,
        toolDiameter: toolDiameter ?? this.toolDiameter,
        depth: depth ?? this.depth,
        stepDown: stepDown ?? this.stepDown,
        settings: settings ?? this.settings,
        result: result ?? this.result,
      );
}

class CamNotifier extends Notifier<CamState> {
  @override
  CamState build() => const CamState();

  void setKind(CamOperationKind k) => state = state.copyWith(kind: k);
  void setTool(double d) => state = state.copyWith(toolDiameter: d);
  void setDepth(double d) => state = state.copyWith(depth: d);
  void setStepDown(double d) => state = state.copyWith(stepDown: d);
  void setPost(String id) => state = state.copyWith(settings: state.settings.copyWith(postId: id));
  void setInches(bool v) => state = state.copyWith(settings: state.settings.copyWith(inches: v));

  /// Generate toolpaths for the selection (or every solid shape when nothing is selected).
  Future<void> generate() async {
    final doc = ref.read(documentProvider);
    final sel = ref.read(selectionProvider);
    final shapes = Footprint.of(doc, only: sel.isEmpty ? null : sel);
    if (shapes.isEmpty) {
      state = state.copyWith(result: AsyncError(const CamFailure('Nothing to machine: add a solid shape first.'), StackTrace.current));
      return;
    }
    state = state.copyWith(result: const AsyncLoading<CamResult?>());
    final op = CamOperation(
      name: state.kind.name,
      kind: state.kind,
      shapes: shapes,
      toolDiameter: state.toolDiameter,
      depth: state.depth,
      stepDown: state.stepDown,
    );
    final result = await AsyncValue.guard<CamResult?>(() => ref.read(camEngineProvider).generate([op], state.settings));
    state = state.copyWith(result: result);
  }
}

final camProvider = NotifierProvider<CamNotifier, CamState>(CamNotifier.new);

final camPostsProvider = FutureProvider<List<PostInfo>>((ref) => ref.watch(camEngineProvider).posts());
