import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/codec/document_codec.dart';
import '../../domain/entities/scene_node.dart';
import '../../domain/ports/geometry_engine.dart';
import '../state/editor_notifier.dart';
import '../state/engine_providers.dart';
import '../state/export_service.dart';
import '../state/scene_providers.dart';
import '../state/selection_notifier.dart';
import '../state/workspace_notifier.dart';
import '../viewport/viewport.dart';
import '../widgets/cam_panel.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/laser_panel.dart';
import '../widgets/shape_palette.dart';
import '../widgets/tool_button.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  static const _wide = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorProvider);
    final sel = ref.watch(selectionProvider);
    final doc = editor.document;
    final ed = ref.read(editorProvider.notifier);
    final panMode = ref.watch(panModeProvider);
    // watched here, not inside the LayoutBuilder callback: Riverpod only allows watch during build
    final workspace = ref.watch(workspaceProvider);

    void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

    Future<void> guarded(Future<void> Function() body) async {
      try {
        await body();
      } on FormatException catch (e) {
        snack(e.message);
      } on EngineFailure catch (e) {
        snack(e.message);
      } catch (e) {
        snack('$e');
      }
    }

    final selectedGroup = sel.length == 1 && doc.find(sel.single) is GroupNode ? sel.single : null;

    final toolbar = [
      ToolButton(icon: Icons.folder_open, tooltip: 'Open…', onPressed: () => guarded(() async {
        final text = await ref.read(importServiceProvider).pickText(extensions: const ['empucad']);
        if (text != null) ed.load(DocumentCodec.decode(text));
      })),
      ToolButton(icon: Icons.save, tooltip: 'Save…', onPressed: () => guarded(() async {
        await ref.read(exportServiceProvider).save(
              suggestedName: '${doc.name}.empucad',
              extension: 'empucad',
              bytes: Uint8List.fromList(utf8.encode(DocumentCodec.encode(doc))),
            );
      })),
      ToolButton(icon: Icons.draw_outlined, tooltip: 'Import SVG…', onPressed: () => guarded(() async {
        final text = await ref.read(importServiceProvider).pickText(extensions: const ['svg']);
        if (text == null) return;
        final node = await ref.read(importSvgProvider)(text, id: ed.nextId(), name: 'SVG');
        ed.addNode(node);
        ref.read(selectionProvider.notifier).select(node.id);
        ref.read(cameraProvider.notifier).frameScene(ref.read(sceneProvider).value);
      })),
      ToolButton(icon: Icons.view_in_ar, tooltip: 'Export STL…', onPressed: doc.roots.isEmpty ? null : () => guarded(() async {
        final bytes = await ref.read(exportStlProvider)(doc);
        if (bytes == null) return snack('Nothing solid to export.');
        await ref.read(exportServiceProvider).save(suggestedName: '${doc.name}.stl', extension: 'stl', bytes: bytes);
      })),
      const VerticalDivider(width: 16),
      ToolButton(icon: Icons.undo, tooltip: 'Undo', onPressed: editor.canUndo ? ed.undo : null),
      ToolButton(icon: Icons.redo, tooltip: 'Redo', onPressed: editor.canRedo ? ed.redo : null),
      const VerticalDivider(width: 16),
      ToolButton(icon: Icons.delete_outline, tooltip: 'Delete', onPressed: sel.isEmpty ? null : () => ed.delete(sel)),
      ToolButton(icon: Icons.join_full, tooltip: 'Group (union)', onPressed: sel.length < 2 ? null : () {
        final id = ed.group(sel);
        if (id != null) ref.read(selectionProvider.notifier).select(id);
      }),
      ToolButton(icon: Icons.call_split, tooltip: 'Ungroup', onPressed: selectedGroup == null ? null : () => ed.ungroup(selectedGroup)),
      ToolButton(icon: Icons.panorama_fish_eye, tooltip: 'Toggle hole', onPressed: sel.isEmpty ? null : () => ed.toggleHole(sel)),
      const VerticalDivider(width: 16),
      ToolButton(icon: Icons.pan_tool_alt_outlined, tooltip: 'Pan mode', active: panMode, onPressed: ref.read(panModeProvider.notifier).toggle),
      ToolButton(icon: Icons.center_focus_strong, tooltip: 'Frame all', onPressed: () => ref.read(cameraProvider.notifier).frameScene(ref.read(sceneProvider).value)),
    ];

    const sidebar = _Sidebar();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (sel.isNotEmpty) ed.delete(sel);
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): ed.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): ed.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): ed.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): ed.redo,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= _wide;
          return Scaffold(
            appBar: AppBar(
              title: Row(children: [
                const Text('EmpuCAD'),
                const SizedBox(width: 16),
                SegmentedButton<Workspace>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: Workspace.design, label: Text('Design')),
                    ButtonSegment(value: Workspace.cnc, label: Text('CNC')),
                    ButtonSegment(value: Workspace.laser, label: Text('Laser')),
                  ],
                  selected: {workspace},
                  onSelectionChanged: (s) => ref.read(workspaceProvider.notifier).select(s.single),
                ),
              ]),
              actions: toolbar,
              toolbarHeight: 48,
            ),
            endDrawer: wide ? null : const Drawer(child: SafeArea(child: sidebar)),
            floatingActionButton: wide
                ? null
                : Builder(builder: (c) => FloatingActionButton.small(onPressed: Scaffold.of(c).openEndDrawer, child: const Icon(Icons.tune))),
            body: wide
                ? const Row(children: [
                    Expanded(child: Viewport()),
                    VerticalDivider(width: 1),
                    SizedBox(width: 340, child: sidebar),
                  ])
                : const Viewport(),
          );
        }),
      ),
    );
  }
}

/// Shape palette and inspector always; the CNC or laser panel follows the active workspace.
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    return SingleChildScrollView(
      child: Column(children: [
        const ShapePalette(),
        const InspectorPanel(),
        switch (ws) {
          Workspace.design => const SizedBox.shrink(),
          Workspace.cnc => const CamPanel(),
          Workspace.laser => const LaserPanel(),
        },
      ]),
    );
  }
}
