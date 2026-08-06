import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Top-left chip showing occurrence id and image version (e.g. `#67 · Original`).
class OccurrenceIdBadge extends StatelessWidget {
  const OccurrenceIdBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final text = label.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardTheme.cardBackground.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cardTheme.cardTextPrimary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: cardTheme.cardTextPrimary.withValues(alpha: 0.78),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
