import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class CardAttributeItem {
  final String label;
  final String value;

  const CardAttributeItem(this.label, this.value);
}

class CardAttributeGrid extends StatelessWidget {
  const CardAttributeGrid({
    super.key,
    required this.attributes,
    required this.isOpen,
  });

  final List<CardAttributeItem> attributes;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final displayed = isOpen ? attributes : attributes.take(3).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final attr in displayed)
          Container(
            width: 104,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: cardTheme.cardTextSecondary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: cardTheme.cardTextSecondary.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attr.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: cardTheme.statLabelStyle(fontSize: 8.0).copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                        color: cardTheme.cardTextSecondary,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  attr.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: cardTheme.statValueStyle(fontSize: 12.0).copyWith(
                        fontWeight: FontWeight.w700,
                        color: cardTheme.cardAccent,
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
