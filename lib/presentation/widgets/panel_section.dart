import 'package:flutter/material.dart';

/// Titled group used by every side panel, so panels look and behave the same.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );
}
