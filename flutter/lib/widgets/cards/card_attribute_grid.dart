import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import 'museum_card_icons.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

/// Soft museum attribute badges — icon well, gold lip, serif value.
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
            lip.withValues(alpha: theme.isLight ? 0.55 : 0.78),
            gold.withValues(alpha: theme.isLight ? 0.18 : 0.28),
            gold.withValues(alpha: theme.isLight ? 0.06 : 0.09),
            gold.withValues(alpha: theme.isLight ? 0.025 : 0.04),
          ],
          stops: const [0.0, 0.16, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: theme.isLight ? 0.10 : 0.16),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.18),
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
              colors: theme.isLight
                  ? const [Color(0xFFFFFCF8), Color(0xFFF3E8DA)]
                  : const [Color(0xFFF7EFE4), Color(0xFFE8D7C4)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 11, 7),
            child: Row(
              children: [
                _AttributeIconWell(label: item.label, gold: gold),
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

class _AttributeIconWell extends StatelessWidget {
  const _AttributeIconWell({
    required this.label,
    required this.gold,
  });

  final String label;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final asset = museumAttributeIconAsset(label);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(gold, const Color(0xFFFFF1D0), 0.35)!,
            gold.withValues(alpha: 0.55),
            const Color(0xFF3A2A1E).withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: gold.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.4),
              radius: 1.0,
              colors: [
                const Color(0xFF2A221C),
                const Color(0xFF15110E),
              ],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: asset != null
                  ? Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    )
                  : MuseumGlyphIcon(
                      glyph: museumGlyphForAttribute(label),
                      size: 18,
                      color: Color.lerp(gold, const Color(0xFFF5E6C8), 0.4),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
