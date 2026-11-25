import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/export_stl.dart';

import '../../application/scene_evaluator.dart';
import '../../data/engine/rust_cam_engine.dart';
import '../../data/engine/rust_geometry_engine.dart';
import '../../domain/ports/cam_engine.dart';
import '../../domain/ports/geometry_engine.dart';

/// The 3D kernel. Override in tests with a fake: `engineProvider.overrideWithValue(FakeGeometryEngine())`.
final engineProvider = Provider<GeometryEngine>((ref) => const RustGeometryEngine());

final camEngineProvider = Provider<CamEngine>((ref) => const RustCamEngine());

final evaluatorProvider = Provider<SceneEvaluator>((ref) => SceneEvaluator(ref.watch(engineProvider)));

final exportStlProvider = Provider<ExportStl>((ref) => ExportStl(ref.watch(evaluatorProvider), ref.watch(engineProvider)));
