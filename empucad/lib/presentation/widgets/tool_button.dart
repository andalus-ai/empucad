import 'package:flutter/material.dart';

/// Icon button with a tooltip; `null` onPressed renders it disabled.
class ToolButton extends StatelessWidget {
  const ToolButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
        isSelected: active,
        style: active ? IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer) : null,
      );
}
