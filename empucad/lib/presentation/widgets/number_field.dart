import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Numeric text field that commits on submit or when focus leaves, and resyncs when the model value
/// changes from elsewhere (undo, drag). Rejects non-numbers and values the caller deems invalid.
class NumberField extends StatefulWidget {
  const NumberField({super.key, required this.label, required this.value, required this.onCommit, this.min, this.suffix = 'mm'});
  final String label;
  final double value;
  final ValueChanged<double> onCommit;
  final double? min;
  final String suffix;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  final FocusNode _focus = FocusNode();

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _c.text = _fmt(widget.value);
  }

  void _commit() {
    final v = double.tryParse(_c.text.trim());
    final ok = v != null && v.isFinite && (widget.min == null || v >= widget.min!);
    if (ok && v != widget.value) widget.onCommit(v);
    if (!ok) _c.text = _fmt(widget.value); // revert rather than keep a bad value on screen
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
        decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix, isDense: true, border: const OutlineInputBorder()),
        onSubmitted: (_) => _commit(),
      );
}
