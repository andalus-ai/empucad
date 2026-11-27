import 'dart:typed_data';

import 'package:empucad/app.dart';
import 'package:empucad/presentation/state/engine_providers.dart';
import 'package:empucad/presentation/state/export_service.dart';
import 'package:empucad/presentation/viewport/canvas_scene_renderer.dart';
import 'package:empucad/presentation/viewport/viewport.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_geometry_engine.dart';

/// No real file dialogs in tests.
class _NoFiles implements ExportService, ImportService {
  @override
  Future<bool> save({required String suggestedName, required String extension, required Uint8List bytes}) async => false;
  @override
  Future<String?> pickText({required List<String> extensions}) async => null;
  @override
  Future<Uint8List?> pickBytes({required List<String> extensions}) async => null;
}

void main() {
  testWidgets('adds a box from the palette, the engine builds it, and undo removes it', (tester) async {
    tester.view.physicalSize = const Size(1400, 900); // wide layout: sidebar visible
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final engine = FakeGeometryEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        engineProvider.overrideWithValue(engine),
        exportServiceProvider.overrideWithValue(_NoFiles()),
        importServiceProvider.overrideWithValue(_NoFiles()),
        // flutter_scene needs a GPU; the software renderer runs in tests
        sceneRendererProvider.overrideWithValue(const CanvasSceneRenderer()),
      ],
      child: const EmpuCadApp(),
    ));

    expect(find.text('EmpuCAD'), findsOneWidget);
    expect(find.text('Select a shape to edit it.'), findsOneWidget);

    await tester.tap(find.text('Box'));
    await tester.pumpAndSettle();
    expect(engine.primitiveCalls, 1, reason: 'the evaluator asked the engine for one box');
    expect(find.text('Select a shape to edit it.'), findsNothing, reason: 'the new box is selected');

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Select a shape to edit it.'), findsOneWidget, reason: 'undo removed the box and its selection');
  });

  testWidgets('the workspace switch shows the CNC and laser panels', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        engineProvider.overrideWithValue(FakeGeometryEngine()),
        exportServiceProvider.overrideWithValue(_NoFiles()),
        importServiceProvider.overrideWithValue(_NoFiles()),
        sceneRendererProvider.overrideWithValue(const CanvasSceneRenderer()),
      ],
      child: const EmpuCadApp(),
    ));

    await tester.tap(find.text('Laser'));
    await tester.pumpAndSettle();
    expect(find.text('LASER BED'), findsOneWidget);
    expect(find.text('LAYERS'), findsOneWidget);
    expect(find.textContaining('Generate laser job'), findsOneWidget);
  });
}
