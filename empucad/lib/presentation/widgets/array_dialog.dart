import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_notifier.dart';
import '../state/selection_notifier.dart';

enum _Mode { linear, grid, circular }

/// Make several copies of the selection in a row, a grid or a circle.
Future<void> showArrayDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ArrayDialog());

class _ArrayDialog extends ConsumerStatefulWidget {
  const _ArrayDialog();
  @override
  ConsumerState<_ArrayDialog> createState() => _ArrayDialogState();
}

class _ArrayDialogState extends ConsumerState<_ArrayDialog> {
  _Mode _mode = _Mode.linear;
  final _c = {
    'count': TextEditingController(text: '3'),
    'dx': TextEditingController(text: '25'),
    'dy': TextEditingController(text: '0'),
    'dz': TextEditingController(text: '0'),
    'rows': TextEditingController(text: '2'),
    'cols': TextEditingController(text: '3'),
    'cx': TextEditingController(text: '0'),
    'cy': TextEditingController(text: '0'),
    'angle': TextEditingController(text: '360'),
  };

  /// Most copies one dialog may create: an array is easy to mistype into thousands of shapes.
  static const _maxCopies = 500;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double? _d(String k) {
    final v = double.tryParse(_c[k]!.text.trim());
    return v != null && v.isFinite ? v : null;
  }

  int? _i(String k) {
    final v = int.tryParse(_c[k]!.text.trim());
    return v != null && v >= 1 ? v : null;
  }

  /// Number of copies this setup would create per selected shape, or null if a field is invalid.
  int? _copies() => switch (_mode) {
        _Mode.linear => _d('dx') == null || _d('dy') == null || _d('dz') == null ? null : _i('count'),
        _Mode.grid => _d('dx') == null || _d('dy') == null || _i('rows') == null || _i('cols') == null ? null : _i('rows')! * _i('cols')! - 1,
        _Mode.circular => _d('cx') == null || _d('cy') == null || _d('angle') == null || _d('angle')! <= 0 ? null : _i('count'),
      };

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectionProvider);
    final copies = _copies();
    final total = copies == null ? null : copies * sel.length;
    final valid = total != null && total >= 1 && total <= _maxCopies && sel.isNotEmpty;

    Widget field(String k, String label, {String suffix = ''}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextField(
              controller: _c[k],
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
            ),
          ),
        );

    return AlertDialog(
      title: const Text('Array'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<_Mode>(
            segments: const [ButtonSegment(value: _Mode.linear, label: Text('Row')), ButtonSegment(value: _Mode.grid, label: Text('Grid')), ButtonSegment(value: _Mode.circular, label: Text('Circle'))],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.single),
          ),
          const SizedBox(height: 12),
          if (_mode == _Mode.linear) ...[
            Row(children: [field('count', 'Extra copies')]),
            const SizedBox(height: 8),
            Row(children: [field('dx', 'Step X', suffix: 'mm'), field('dy', 'Step Y', suffix: 'mm'), field('dz', 'Step Z', suffix: 'mm')]),
          ],
          if (_mode == _Mode.grid) ...[
            Row(children: [field('rows', 'Rows'), field('cols', 'Columns')]),
            const SizedBox(height: 8),
            Row(children: [field('dx', 'Spacing X', suffix: 'mm'), field('dy', 'Spacing Y', suffix: 'mm')]),
          ],
          if (_mode == _Mode.circular) ...[
            Row(children: [field('count', 'Extra copies'), field('angle', 'Spread', suffix: '°')]),
            const SizedBox(height: 8),
            Row(children: [field('cx', 'Centre X', suffix: 'mm'), field('cy', 'Centre Y', suffix: 'mm')]),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('360° spaces the original and the copies evenly round the circle.', style: Theme.of(context).textTheme.bodySmall)),
          ],
          const SizedBox(height: 12),
          Text(
            sel.isEmpty
                ? 'Select something first.'
                : total == null
                    ? 'Check the numbers.'
                    : total > _maxCopies
                        ? 'That would make $total copies; the limit is $_maxCopies.'
                        : 'Makes $total new ${total == 1 ? 'shape' : 'shapes'}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: !valid
              ? null
              : () {
                  final ed = ref.read(editorProvider.notifier);
                  final ids = switch (_mode) {
                    _Mode.linear => ed.linearArray(sel, count: _i('count')!, dx: _d('dx')!, dy: _d('dy')!, dz: _d('dz')!),
                    _Mode.grid => ed.gridArray(sel, rows: _i('rows')!, columns: _i('cols')!, dx: _d('dx')!, dy: _d('dy')!),
                    _Mode.circular => ed.circularArray(sel, count: _i('count')!, cx: _d('cx')!, cy: _d('cy')!, totalAngle: _d('angle')!),
                  };
                  ref.read(selectionProvider.notifier).setAll([...sel, ...ids]);
                  Navigator.of(context).pop();
                },
          child: const Text('Make copies'),
        ),
      ],
    );
  }
}
