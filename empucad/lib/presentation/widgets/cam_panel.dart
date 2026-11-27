import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/build_cam_operation.dart';
import '../../domain/cnc/tool_library.dart';
import '../../domain/ports/cam_engine.dart';
import '../state/editor_notifier.dart';
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
    CamOperationKind.vcarve: 'V-carve',
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
        _ToolPicker(kind: cam.kind, selectedId: cam.toolId),
        gap(),
        Row(children: [
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
        if (ToolCompat.wantsDogbones(cam.kind))
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Dogbone corners'),
            subtitle: const Text('Relief so a square part fits the inside corners'),
            value: cam.dogbones,
            onChanged: n.setDogbones,
          ),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Arcs (G2/G3)'), subtitle: const Text('Smaller, smoother programs'), value: cam.settings.arcs, onChanged: n.setArcs),
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

/// Tool dropdown (only tools that suit the operation) with the chosen tool's settings editable below.
class _ToolPicker extends ConsumerWidget {
  const _ToolPicker({required this.kind, required this.selectedId});
  final CamOperationKind kind;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(documentProvider.select((d) => d.tools));
    final ed = ref.read(editorProvider.notifier);
    final cam = ref.read(camProvider.notifier);
    final suitable = [for (final t in lib.tools) if (ToolCompat.allows(kind, t.kind)) t];
    final tool = ToolCompat.resolve(lib, kind, selectedId);
    if (tool == null) return Text('No tool in the library suits this operation.', style: TextStyle(color: Theme.of(context).colorScheme.error));
    Widget gap() => const SizedBox(height: 8);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('tool-${tool.id}-${suitable.length}'),
            initialValue: tool.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tool', isDense: true, border: OutlineInputBorder()),
            items: [for (final t in suitable) DropdownMenuItem(value: t.id, child: Text('T${lib.numberOf(t.id)}  ${t.name}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : cam.setTool(v),
          ),
        ),
        IconButton(tooltip: 'Duplicate tool', icon: const Icon(Icons.copy_all_outlined), onPressed: () => cam.setTool(ed.duplicateTool(tool))),
        IconButton(tooltip: 'Delete tool', icon: const Icon(Icons.delete_outline), onPressed: lib.tools.length <= 1 ? null : () => ed.removeTool(tool.id)),
      ]),
      gap(),
      Row(children: [
        Expanded(child: NumberField(label: 'Diameter', value: tool.diameter, min: 0.05, onCommit: (v) => ed.updateTool(tool.copyWith(diameter: v)))),
        if (tool.isV) ...[
          const SizedBox(width: 6),
          Expanded(child: NumberField(label: 'Angle', value: tool.angle, min: 1, suffix: '°', onCommit: (v) => ed.updateTool(tool.copyWith(angle: v.clamp(1.0, 179.0))))),
        ],
      ]),
      gap(),
      Row(children: [
        Expanded(child: NumberField(label: 'Feed', value: tool.feed, min: 1, suffix: 'mm/min', onCommit: (v) => ed.updateTool(tool.copyWith(feed: v)))),
        const SizedBox(width: 6),
        Expanded(child: NumberField(label: 'Plunge', value: tool.plunge, min: 1, suffix: 'mm/min', onCommit: (v) => ed.updateTool(tool.copyWith(plunge: v)))),
        const SizedBox(width: 6),
        Expanded(child: NumberField(label: 'RPM', value: tool.rpm, min: 0, suffix: '', onCommit: (v) => ed.updateTool(tool.copyWith(rpm: v)))),
      ]),
      if (kind == CamOperationKind.vcarve)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Groove depth follows the shape width. Diameter is the bit\'s widest cut; Depth is the limit.', style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }
}
