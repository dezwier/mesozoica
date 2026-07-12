import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Frosted section container matching the front attribute panel.
class CardSectionPanel extends StatelessWidget {
  const CardSectionPanel({
    super.key,
    required this.label,
    required this.child,
    this.expandChild = false,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
  });

  final String label;
  final Widget child;
  final bool expandChild;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return DecoratedBox(
      decoration: cardTheme.factPanelDecoration(),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label.toUpperCase(),
              style: cardTheme.sectionLabelStyle(fontSize: 9),
            ),
            const SizedBox(height: 6),
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
