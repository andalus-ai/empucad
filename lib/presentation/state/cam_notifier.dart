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
    this.tabCount = 0,
    this.tabWidth = 6.0,
    this.tabHeight = 1.0,
    this.rampLength = 0.0,
    this.settings = const CamSettings(),
    this.result = const AsyncData<CamResult?>(null),
  });
  final CamOperationKind kind;
  final double toolDiameter, depth, stepDown, tabWidth, tabHeight, rampLength;
  final int tabCount;
  final CamSettings settings;
  final AsyncValue<CamResult?> result;

  CamState copyWith({
    CamOperationKind? kind,
    double? toolDiameter,
    double? depth,
    double? stepDown,
    int? tabCount,
    double? tabWidth,
    double? tabHeight,
    double? rampLength,
    CamSettings? settings,
    AsyncValue<CamResult?>? result,
  }) =>
      CamState(
        kind: kind ?? this.kind,
        toolDiameter: toolDiameter ?? this.toolDiameter,
        depth: depth ?? this.depth,
        stepDown: stepDown ?? this.stepDown,
        tabCount: tabCount ?? this.tabCount,
        tabWidth: tabWidth ?? this.tabWidth,
        tabHeight: tabHeight ?? this.tabHeight,
        rampLength: rampLength ?? this.rampLength,
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
  void setTabCount(int n) => state = state.copyWith(tabCount: n);
  void setTabWidth(double v) => state = state.copyWith(tabWidth: v);
  void setTabHeight(double v) => state = state.copyWith(tabHeight: v);
  void setRamp(double v) => state = state.copyWith(rampLength: v);
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
    final isProfile = state.kind == CamOperationKind.profileOutside || state.kind == CamOperationKind.profileInside || state.kind == CamOperationKind.profileOn;
    final op = CamOperation(
      name: state.kind.name,
      kind: state.kind,
      shapes: shapes,
      toolDiameter: state.toolDiameter,
      depth: state.depth,
      stepDown: state.stepDown,
      tabCount: isProfile ? state.tabCount : 0,
      tabWidth: state.tabWidth,
      tabHeight: state.tabHeight,
      rampLength: state.rampLength,
    );
    final result = await AsyncValue.guard<CamResult?>(() => ref.read(camEngineProvider).generate([op], state.settings));
    state = state.copyWith(result: result);
  }
}

final camProvider = NotifierProvider<CamNotifier, CamState>(CamNotifier.new);

final camPostsProvider = FutureProvider<List<PostInfo>>((ref) => ref.watch(camEngineProvider).posts());
