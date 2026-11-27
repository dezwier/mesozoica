import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Shared vertical stack for card backs — everything visible, no accordion.
///
/// Scales down as a unit if content is taller than the slot. Linked-card
/// rows inside sections may still scroll horizontally on their own.
class CardBackBody extends StatelessWidget {
  const CardBackBody({
    super.key,
    required this.children,
    this.bottom,
    this.gap = 8,
  });

  final List<Widget> children;

  /// Pinned under the scaled stack (e.g. tool action row).
  final Widget? bottom;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final stack = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: constraints.maxWidth, child: stack),
                ),
              );
            },
          ),
        ),
        if (bottom != null) ...[SizedBox(height: gap), bottom!],
      ],
    );
  }
}

/// Gold-outlined panel for a back-face section. Omit [title] for an unlabeled card.
class CardBackSection extends StatelessWidget {
  const CardBackSection({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(8, 8, 8, 8),
    this.expandChild = false,
  });

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final label = title?.trim();
    return DecoratedBox(
      decoration: cardTheme.museumPanelDecoration(),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (label != null && label.isNotEmpty) ...[
              Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: cardTheme
                    .sectionLabelStyle(fontSize: 9)
                    .copyWith(
                      fontFamily: DinoCardTheme.titleFontFamily,
                      color: cardTheme.cardAccent,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
            ],
            if (expandChild) Expanded(child: child) else child,
          ],
        ),
      ),
    );
  }
}
