import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'museum_card_frame.dart';

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
///
/// When [title] is set, a left-inset diagonal tab sits on the top rim
/// (Attributes / Cladogram style).
class CardBackSection extends StatelessWidget {
  const CardBackSection({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 9, 10, 10),
    this.expandChild = false,
  });

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expandChild;

  static const _tabOverlap = 9.0;

  @override
  Widget build(BuildContext context) {
    final label = title?.trim();
    final hasTab = label != null && label.isNotEmpty;
    final panel = MuseumInnerCard(
      padding: padding,
      child: Column(
        mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTab) const SizedBox(height: 6),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );

    if (!hasTab) return panel;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _tabOverlap),
          child: panel,
        ),
        Positioned(left: 0, top: 0, child: MuseumSectionTab(label: label)),
      ],
    );
  }
}
