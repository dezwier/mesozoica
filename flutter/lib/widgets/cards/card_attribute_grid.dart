import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'museum_card_icons.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

/// Cream attribute rows — engraved icon, small-caps label, serif value.
class CardAttributeGrid extends StatelessWidget {
  const CardAttributeGrid({
    super.key,
    required this.attributes,
    this.isOpen = true,
    this.columns,
    this.fill = false,
  });

  final List<CardAttributeItem> attributes;

  /// Kept for call-site compatibility; all attributes are always shown.
  final bool isOpen;

  /// Kept for call-site compatibility. Rows are always a single column.
  final int? columns;

  /// Stretch each row to share the parent's height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (attributes.isEmpty) return const SizedBox.shrink();
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (var i = 0; i < attributes.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          if (fill)
            Expanded(
              child: _AttributeRow(item: attributes[i], theme: cardTheme),
            )
          else
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
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A3A2A1E),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            MuseumGlyphIcon(
              glyph: museumGlyphForAttribute(item.label),
              size: 24,
              color: theme.museumTileLabel,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .statLabelStyle(fontSize: 7.5)
                        .copyWith(
                          fontFamily: DinoCardTheme.titleFontFamily,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.05,
                          height: 1.05,
                          color: theme.museumTileLabel,
                        ),
                  ),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme
                        .titleStyle(fontSize: 12.5, color: theme.museumTileInk)
                        .copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.02,
                          height: 1.05,
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
