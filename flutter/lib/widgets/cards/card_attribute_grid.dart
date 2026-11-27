import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

/// Compact attribute chips — one mini card per attribute, always fully shown.
class CardAttributeGrid extends StatelessWidget {
  const CardAttributeGrid({
    super.key,
    required this.attributes,
    this.isOpen = true,
    this.columns,
  });

  final List<CardAttributeItem> attributes;

  /// Kept for call-site compatibility; all attributes are always shown.
  final bool isOpen;

  /// Fixed column count. When null, picks 2 (or 3 for 5–6 attrs).
  final int? columns;

  @override
  Widget build(BuildContext context) {
    if (attributes.isEmpty) return const SizedBox.shrink();
    final cardTheme = DinoCardTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final count = attributes.length;
        final cols = columns ?? (count <= 4 ? 2 : (count <= 6 ? 3 : 2));
        const gap = 6.0;
        final cellW = maxW.isFinite && maxW > 0
            ? (maxW - gap * (cols - 1)) / cols
            : 140.0;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final attr in attributes)
              SizedBox(
                width: cellW,
                child: _AttributeCard(item: attr, theme: cardTheme),
              ),
          ],
        );
      },
    );
  }
}

class _AttributeCard extends StatelessWidget {
  const _AttributeCard({required this.item, required this.theme});

  final CardAttributeItem item;
  final DinoCardTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.cardAccent.withValues(alpha: theme.isLight ? 0.08 : 0.12),
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.cardAccent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme
                  .statLabelStyle(fontSize: 8)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: theme.cardTextSecondary,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              item.value,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme
                  .statValueStyle(fontSize: 13)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.cardAccent,
                    height: 1.15,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
