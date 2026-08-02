import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Section container styled like profile cards (elevation, radius).
class CardSectionPanel extends StatelessWidget {
  const CardSectionPanel({
    super.key,
    this.label,
    required this.child,
    this.expandChild = false,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
    this.clipChild = false,
  });

  final String? label;
  final Widget child;
  final bool expandChild;
  final EdgeInsetsGeometry padding;
  final bool clipChild;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null && label!.isNotEmpty) ...[
            Text(
              label!.toUpperCase(),
              style: cardTheme.sectionLabelStyle(fontSize: 9),
            ),
            const SizedBox(height: 6),
          ],
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );

    if (clipChild) {
      content = ClipRRect(
        borderRadius:
            BorderRadius.circular(DinoCardTheme.factPanelBorderRadius),
        child: content,
      );
    }

    final panel = DecoratedBox(
      decoration: cardTheme.factPanelDecoration(context),
      child: content,
    );
    if (expandChild) {
      return SizedBox.expand(child: panel);
    }
    return panel;
  }
}
