import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ports/cam_engine.dart';
import '../state/cam_notifier.dart';
import '../state/export_service.dart';
import 'number_field.dart';
import 'panel_section.dart';
import 'toolpath_preview.dart';

class CamPanel extends ConsumerWidget {
  const CamPanel({super.key});

  static const _labels = {
    CamOperationKind.profileOutside: 'Cut out (outside)',
    CamOperationKind.profileInside: 'Cut inside',
    CamOperationKind.profileOn: 'On the line',
    CamOperationKind.pocket: 'Pocket',
    CamOperationKind.engrave: 'Engrave',
    CamOperationKind.drill: 'Drill',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cam = ref.watch(camProvider);
    final n = ref.read(camProvider.notifier);
    final posts = ref.watch(camPostsProvider).value ?? const <PostInfo>[];
    final result = cam.result;
    Widget gap() => const SizedBox(height: 8);

    return PanelSection(
      title: 'CNC',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<CamOperationKind>(
          initialValue: cam.kind,
          decoration: const InputDecoration(labelText: 'Operation', isDense: true, border: OutlineInputBorder()),
          items: [for (final e in _labels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => v == null ? null : n.setKind(v),
        ),
        gap(),
        Row(children: [
          Expanded(child: NumberField(label: 'Tool Ø', value: cam.toolDiameter, min: 0.05, onCommit: n.setTool)),
          const SizedBox(width: 6),
          Expanded(child: NumberField(label: 'Depth', value: cam.depth, min: 0.05, onCommit: n.setDepth)),
          const SizedBox(width: 6),
          Expanded(child: NumberField(label: 'Per pass', value: cam.stepDown, min: 0.05, onCommit: n.setStepDown)),
        ]),
        gap(),
        Row(children: [
          Expanded(child: NumberField(label: 'Ramp', value: cam.rampLength, min: 0, onCommit: n.setRamp)),
          const SizedBox(width: 6),
          if (cam.kind == CamOperationKind.profileOutside || cam.kind == CamOperationKind.profileInside || cam.kind == CamOperationKind.profileOn)
            Expanded(child: NumberField(label: 'Tabs', value: cam.tabCount.toDouble(), min: 0, suffix: '', onCommit: (v) => n.setTabCount(v.round()))),
          if (cam.tabCount > 0) ...[
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Tab width', value: cam.tabWidth, min: 0.1, onCommit: n.setTabWidth)),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Tab high', value: cam.tabHeight, min: 0.1, onCommit: n.setTabHeight)),
          ],
        ]),
        gap(),
        if (posts.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: posts.any((p) => p.id == cam.settings.postId) ? cam.settings.postId : posts.first.id,
            decoration: const InputDecoration(labelText: 'Controller', isDense: true, border: OutlineInputBorder()),
            items: [for (final p in posts) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => v == null ? null : n.setPost(v),
          ),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Inches'), value: cam.settings.inches, onChanged: n.setInches),
        FilledButton.icon(
          onPressed: result.isLoading ? null : n.generate,
          icon: const Icon(Icons.route),
          label: const Text('Generate toolpath'),
        ),
        gap(),
        switch (result) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => Text('$error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          AsyncData(:final value) when value == null => const SizedBox.shrink(),
          AsyncData(:final value) => _Result(result: value!, postExt: value.fileExtension),
        },
      ]),
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result({required this.result, required this.postExt});
  final CamResult result;
  final String postExt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mins = (result.seconds / 60);
    final time = mins < 1 ? '${result.seconds.round()} s' : '${mins.floor()} min ${(result.seconds % 60).round()} s';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ToolpathPreview(moves: result.preview),
      const SizedBox(height: 6),
      Text('Estimated run time: $time', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        icon: const Icon(Icons.download),
        label: Text('Save .$postExt'),
        onPressed: () async {
          final bytes = Uint8List.fromList(utf8.encode(result.gcode));
          await ref.read(exportServiceProvider).save(suggestedName: 'empucad.$postExt', extension: postExt, bytes: bytes);
        },
      ),
    ]);
  }
}
