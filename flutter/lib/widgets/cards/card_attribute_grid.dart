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
    this.isOpen = false,
  });

  final List<CardAttributeItem> attributes;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final displayed = isOpen ? attributes : attributes.take(3).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        for (final attr in displayed)
          SizedBox(
            width: 102,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attr.label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: cardTheme.statLabelStyle(fontSize: 8.5).copyWith(
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
                  style: cardTheme.statValueStyle(fontSize: 13.0).copyWith(
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
