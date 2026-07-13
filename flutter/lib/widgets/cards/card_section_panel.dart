import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Frosted section container matching the front attribute panel.
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

    return DecoratedBox(
      decoration: cardTheme.factPanelDecoration(),
      child: content,
    );
  }
}
