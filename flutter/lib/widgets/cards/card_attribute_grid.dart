import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'museum_card_icons.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

/// Soft museum attribute badges — bare icon, gold lip, themed fill.
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
          if (i > 0) const SizedBox(height: 7),
          if (fill)
            Expanded(
              child: _AttributeBadge(item: attributes[i], theme: cardTheme),
            )
          else
            _AttributeBadge(item: attributes[i], theme: cardTheme),
        ],
      ],
    );
  }
}

class _AttributeBadge extends StatelessWidget {
  const _AttributeBadge({required this.item, required this.theme});

  final CardAttributeItem item;
  final DinoCardTheme theme;

  @override
  Widget build(BuildContext context) {
    final gold = theme.cardAccent;
    final lip = Color.lerp(gold, const Color(0xFFFFF1D0), 0.45)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lip.withValues(alpha: theme.isLight ? 0.55 : 0.72),
            gold.withValues(alpha: theme.isLight ? 0.18 : 0.26),
            gold.withValues(alpha: theme.isLight ? 0.06 : 0.08),
            gold.withValues(alpha: theme.isLight ? 0.025 : 0.035),
          ],
          stops: const [0.0, 0.16, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: theme.isLight ? 0.10 : 0.14),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: const Color(
              0xFF000000,
            ).withValues(alpha: theme.isLight ? 0.12 : 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(0.85),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15.2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.museumTileColor, theme.museumTileColorEnd],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 11, 7),
            child: Row(
              children: [
                _AttributeIcon(label: item.label, gold: gold),
                const SizedBox(width: 10),
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
                              letterSpacing: 1.15,
                              height: 1.05,
                              color: theme.museumTileLabel,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme
                            .titleStyle(
                              fontSize: 13,
                              color: theme.museumTileInk,
                            )
                            .copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.02,
                              height: 1.1,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttributeIcon extends StatelessWidget {
  const _AttributeIcon({required this.label, required this.gold});

  final String label;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final asset = museumAttributeIconAsset(label);
    return SizedBox(
      width: 28,
      height: 28,
      child: asset != null
          ? Image.asset(
              asset,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            )
          : MuseumGlyphIcon(
              glyph: museumGlyphForAttribute(label),
              size: 22,
              color: Color.lerp(gold, const Color(0xFFF5E6C8), 0.35),
            ),
    );
  }
}
