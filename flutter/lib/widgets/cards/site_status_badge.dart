import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

/// Subtle status chip for field site cards.
class SiteStatusBadge extends StatelessWidget {
  const SiteStatusBadge({
    super.key,
    required this.status,
    this.onPressed,
  });

  final String status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final label = capitalizeLeadingLetter(status.trim());
    if (label.isEmpty) return const SizedBox.shrink();

    final chip = DecoratedBox(
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
          label,
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

    if (onPressed == null) return chip;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: chip,
      ),
    );
  }
}
