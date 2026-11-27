import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'museum_card_icons.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

/// Cream attribute rows — icon, small-caps label, serif value. Always fully shown.
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

  /// Kept for call-site compatibility. Rows are always a single column.
  final int? columns;

  @override
  Widget build(BuildContext context) {
    if (attributes.isEmpty) return const SizedBox.shrink();
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < attributes.length; i++) ...[
          if (i > 0) const SizedBox(height: 5),
          _AttributeRow(item: attributes[i], theme: cardTheme),
        ],
      ],
    );
  }
}

class _AttributeRow extends StatelessWidget {
  const _AttributeRow({required this.item, required this.theme});

  final CardAttributeItem item;
  final DinoCardTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.museumTileColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3A2A1E).withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: theme.museumTileLabel.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: MuseumGlyphIcon(
                glyph: museumGlyphForAttribute(item.label),
                size: 16,
                color: theme.museumTileLabel,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .statLabelStyle(fontSize: 7.5)
                        .copyWith(
                          fontFamily: DinoCardTheme.titleFontFamily,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: theme.museumTileLabel,
                        ),
                  ),
                  Text(
                    item.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .titleStyle(fontSize: 12.5, color: theme.museumTileInk)
                        .copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.15,
                          height: 1.15,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
