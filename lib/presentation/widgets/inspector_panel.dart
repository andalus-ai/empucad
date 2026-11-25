import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/scene_node.dart';
import '../state/editor_notifier.dart';
import '../state/selection_notifier.dart';
import 'number_field.dart';
import 'panel_section.dart';

/// Edits the single selected node: size (shapes), position, rotation, hole flag.
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(documentProvider);
    final sel = ref.watch(selectionProvider);
    final node = sel.length == 1 ? doc.find(sel.single) : null;
    if (node == null) {
      return PanelSection(
        title: 'Inspector',
        child: Text(sel.isEmpty ? 'Select a shape to edit it.' : '${sel.length} selected', style: Theme.of(context).textTheme.bodySmall),
      );
    }
    final ed = ref.read(editorProvider.notifier);
    final p = node.placement;
    Widget row(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [for (final c in children) Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: c))]),
        );

    return PanelSection(
      title: node.name,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Hole'),
        Switch(value: node.isHole, onChanged: (_) => ed.toggleHole({node.id})),
      ]),
      child: Column(children: [
        if (node is ShapeNode) ...[
          if (node.kind == ShapeKind.box)
            row([
              NumberField(label: 'Width', value: node.width, min: 0.01, onCommit: (v) => ed.resize(node.id, width: v)),
              NumberField(label: 'Depth', value: node.depth, min: 0.01, onCommit: (v) => ed.resize(node.id, depth: v)),
            ])
          else
            row([NumberField(label: 'Diameter', value: node.width, min: 0.01, onCommit: (v) => ed.resize(node.id, width: v))]),
          row([NumberField(label: 'Height', value: node.height, min: 0.01, onCommit: (v) => ed.resize(node.id, height: v))]),
        ],
        row([
          NumberField(label: 'X', value: p.x, onCommit: (v) => ed.setPlacement(node.id, p.copyWith(x: v))),
          NumberField(label: 'Y', value: p.y, onCommit: (v) => ed.setPlacement(node.id, p.copyWith(y: v))),
          NumberField(label: 'Z', value: p.z, onCommit: (v) => ed.setPlacement(node.id, p.copyWith(z: v))),
        ]),
        row([
          NumberField(label: 'Rot X', value: p.rx, suffix: '°', onCommit: (v) => ed.setPlacement(node.id, p.copyWith(rx: v))),
          NumberField(label: 'Rot Y', value: p.ry, suffix: '°', onCommit: (v) => ed.setPlacement(node.id, p.copyWith(ry: v))),
          NumberField(label: 'Rot Z', value: p.rz, suffix: '°', onCommit: (v) => ed.setPlacement(node.id, p.copyWith(rz: v))),
        ]),
      ]),
    );
  }
}
