import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/generate_laser_job.dart';
import '../../domain/laser/laser_models.dart';
import '../state/editor_notifier.dart';
import '../state/export_service.dart';
import '../state/laser_notifier.dart';
import '../state/selection_notifier.dart';
import 'laser_preview.dart';
import 'number_field.dart';
import 'panel_section.dart';

/// The laser workspace sidebar: machine, layers (assign the selection to a layer), image burn, and
/// the generated job with a preview.
class LaserPanel extends ConsumerWidget {
  const LaserPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Column(children: [_MachineSection(), _LayersSection(), _ImageSection(), _ResultSection()]);
}

class _MachineSection extends ConsumerWidget {
  const _MachineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(documentProvider.select((d) => d.laser.machine));
    final ed = ref.read(editorProvider.notifier);
    return PanelSection(
      title: 'Laser bed',
      child: Column(children: [
        Row(children: [
          Expanded(child: NumberField(label: 'Width', value: m.bedWidth, min: 1, onCommit: (v) => ed.setLaserMachine(m.copyWith(bedWidth: v)))),
          const SizedBox(width: 6),
          Expanded(child: NumberField(label: 'Height', value: m.bedHeight, min: 1, onCommit: (v) => ed.setLaserMachine(m.copyWith(bedHeight: v)))),
          const SizedBox(width: 6),
          Expanded(child: NumberField(label: 'S max', value: m.sMax, min: 1, suffix: '', onCommit: (v) => ed.setLaserMachine(m.copyWith(sMax: v)))),
        ]),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Dynamic power (M4)'),
          subtitle: const Text('Power follows speed. Best for engraving.'),
          value: m.dynamicPower,
          onChanged: (v) => ed.setLaserMachine(m.copyWith(dynamicPower: v)),
        ),
      ]),
    );
  }
}

class _LayersSection extends ConsumerWidget {
  const _LayersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(documentProvider.select((d) => d.laser));
    final sel = ref.watch(selectionProvider);
    final ed = ref.read(editorProvider.notifier);
    final counts = <int, int>{};
    for (final l in setup.layerOf.values) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    return PanelSection(
      title: 'Layers',
      child: Column(children: [
        for (final l in setup.layers)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 8, backgroundColor: Color(l.color)),
            title: Text('${l.name}${counts[l.index] == null ? '' : '  (${counts[l.index]})'}'),
            subtitle: Text('${l.mode == LaserLayerMode.fill ? 'Fill' : 'Line'}  ${_n(l.speed)} mm/s  ${_n(l.power)}%'),
            trailing: Switch(value: l.enabled, onChanged: (v) => ed.updateLaserLayer(l.copyWith(enabled: v))),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(children: [
                  SegmentedButton<LaserLayerMode>(
                    segments: const [ButtonSegment(value: LaserLayerMode.line, label: Text('Line')), ButtonSegment(value: LaserLayerMode.fill, label: Text('Fill'))],
                    selected: {l.mode},
                    onSelectionChanged: (s) => ed.updateLaserLayer(l.copyWith(mode: s.single)),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: NumberField(label: 'Speed', value: l.speed, min: 0.1, suffix: 'mm/s', onCommit: (v) => ed.updateLaserLayer(l.copyWith(speed: v)))),
                    const SizedBox(width: 6),
                    Expanded(child: NumberField(label: 'Power', value: l.power, min: 0, suffix: '%', onCommit: (v) => ed.updateLaserLayer(l.copyWith(power: v.clamp(0, 100))))),
                    const SizedBox(width: 6),
                    Expanded(child: NumberField(label: 'Passes', value: l.passes.toDouble(), min: 1, suffix: '', onCommit: (v) => ed.updateLaserLayer(l.copyWith(passes: v.round().clamp(1, 99))))),
                  ]),
                  if (l.mode == LaserLayerMode.fill) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: NumberField(label: 'Line gap', value: l.interval, min: 0.01, onCommit: (v) => ed.updateLaserLayer(l.copyWith(interval: v)))),
                      const SizedBox(width: 6),
                      Expanded(child: NumberField(label: 'Angle', value: l.angle, suffix: '°', onCommit: (v) => ed.updateLaserLayer(l.copyWith(angle: v)))),
                      const SizedBox(width: 6),
                      Expanded(child: NumberField(label: 'Overscan', value: l.overscan, min: 0, onCommit: (v) => ed.updateLaserLayer(l.copyWith(overscan: v)))),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.input),
                      label: Text(sel.isEmpty ? 'Select shapes to assign' : 'Assign ${sel.length} selected here'),
                      onPressed: sel.isEmpty ? null : () => ed.assignLaserLayer(sel, l.index),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Shapes with no layer burn on "${setup.layers.first.name}".', style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: ref.watch(laserProvider.select((s) => s.result.isLoading)) ? null : ref.read(laserProvider.notifier).generateLayers,
          icon: const Icon(Icons.local_fire_department_outlined),
          label: Text(sel.isEmpty ? 'Generate laser job' : 'Generate for selection'),
        ),
      ]),
    );
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _ImageSection extends ConsumerWidget {
  const _ImageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(documentProvider.select((d) => d.laser.raster));
    final loading = ref.watch(laserProvider.select((s) => s.result.isLoading));
    final n = ref.read(laserProvider.notifier);
    final image = asset?.image;
    final r = asset?.settings ?? const RasterSettings();
    return PanelSection(
      title: 'Image engraving',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(onPressed: n.loadImage, icon: const Icon(Icons.image_outlined), label: Text(asset?.name ?? 'Load image…')),
        if (image != null) ...[
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: n.removeImage, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Remove image'))),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: NumberField(label: 'Width', value: r.widthMm, min: 1, onCommit: (v) => n.setRaster(r.copyWith(widthMm: v)))),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'X', value: r.x, onCommit: (v) => n.setRaster(r.copyWith(x: v)))),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Y', value: r.y, onCommit: (v) => n.setRaster(r.copyWith(y: v)))),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Height ${GenerateRasterJob.heightFor(image, r.widthMm).toStringAsFixed(1)} mm (from the image shape). X, Y is the bottom-left corner.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: NumberField(label: 'Speed', value: r.speed, min: 0.1, suffix: 'mm/s', onCommit: (v) => n.setRaster(r.copyWith(speed: v)))),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Min', value: r.powerMin, min: 0, suffix: '%', onCommit: (v) => n.setRaster(r.copyWith(powerMin: v)))),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Max', value: r.powerMax, min: 0, suffix: '%', onCommit: (v) => n.setRaster(r.copyWith(powerMax: v)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: NumberField(label: 'Line gap', value: r.interval, min: 0.01, onCommit: (v) => n.setRaster(r.copyWith(interval: v)))),
            const SizedBox(width: 6),
            Expanded(child: NumberField(label: 'Overscan', value: r.overscan, min: 0, onCommit: (v) => n.setRaster(r.copyWith(overscan: v)))),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<RasterMode>(
            segments: const [ButtonSegment(value: RasterMode.grayscale, label: Text('Grayscale')), ButtonSegment(value: RasterMode.dither, label: Text('Dither'))],
            selected: {r.mode},
            onSelectionChanged: (s) => n.setRaster(r.copyWith(mode: s.single)),
          ),
          SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Invert (burn the light parts)'), value: r.invert, onChanged: (v) => n.setRaster(r.copyWith(invert: v))),
          FilledButton.icon(onPressed: loading ? null : n.generateImage, icon: const Icon(Icons.local_fire_department_outlined), label: const Text('Generate image job')),
        ],
      ]),
    );
  }
}

class _ResultSection extends ConsumerWidget {
  const _ResultSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(laserProvider.select((s) => s.result));
    final machine = ref.watch(documentProvider.select((d) => d.laser.machine));
    return switch (result) {
      AsyncLoading() => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      AsyncError(:final error) => PanelSection(title: 'Laser job', child: Text(_msg(error), style: TextStyle(color: Theme.of(context).colorScheme.error))),
      AsyncData(:final value) when value == null => const SizedBox.shrink(),
      AsyncData(:final value) => PanelSection(
          title: 'Laser job',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LaserPreview(moves: value!.preview, bedWidth: machine.bedWidth, bedHeight: machine.bedHeight, sMax: machine.sMax),
            const SizedBox(height: 6),
            Text('Estimated burn time: ${_time(value.seconds)}', style: Theme.of(context).textTheme.bodySmall),
            for (final w in value.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.warning_amber, size: 16, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: Theme.of(context).textTheme.bodySmall)),
                ]),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Save .gcode'),
              onPressed: () => ref.read(exportServiceProvider).save(suggestedName: 'empucad-laser.gcode', extension: 'gcode', bytes: Uint8List.fromList(utf8.encode(value.gcode))),
            ),
          ]),
        ),
    };
  }

  static String _msg(Object e) => e is LaserFailure ? e.message : '$e';

  static String _time(double s) {
    final m = s / 60;
    return m < 1 ? '${s.round()} s' : '${m.floor()} min ${(s % 60).round()} s';
  }
}
