import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/scene_node.dart';
import '../state/editor_notifier.dart';
import '../state/selection_notifier.dart';
import 'panel_section.dart';

class ShapePalette extends ConsumerWidget {
  const ShapePalette({super.key});

  static const _items = <(ShapeKind, IconData, String)>[
    (ShapeKind.box, Icons.crop_square, 'Box'),
    (ShapeKind.cylinder, Icons.circle_outlined, 'Cylinder'),
    (ShapeKind.sphere, Icons.sports_basketball_outlined, 'Sphere'),
    (ShapeKind.cone, Icons.change_history, 'Cone'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => PanelSection(
        title: 'Shapes',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (kind, icon, label) in _items)
            ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () {
                final id = ref.read(editorProvider.notifier).addShape(kind);
                ref.read(selectionProvider.notifier).select(id);
              },
            ),
        ]),
      );
}
