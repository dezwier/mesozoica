import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Section container styled like profile cards (elevation, radius).
class CardSectionPanel extends StatelessWidget {
  const CardSectionPanel({
    super.key,
    this.label,
    this.labelWidget,
    required this.child,
    this.expandChild = false,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 10, 8),
    this.labelGap = 6,
    this.clipChild = false,
    this.labelFontSize = 9,
  });

  final String? label;

  /// When set, replaces the default uppercased [label] text.
  final Widget? labelWidget;
  final Widget child;
  final bool expandChild;
  final EdgeInsetsGeometry padding;
  final double labelGap;
  final bool clipChild;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final resolvedLabel =
        labelWidget ??
        (label != null && label!.isNotEmpty
            ? Text(
                label!.toUpperCase(),
                style: cardTheme.sectionLabelStyle(fontSize: labelFontSize),
              )
            : null);

    Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolvedLabel != null) ...[
            resolvedLabel,
            SizedBox(height: labelGap),
          ],
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );

    if (clipChild) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(
          DinoCardTheme.factPanelBorderRadius,
        ),
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
