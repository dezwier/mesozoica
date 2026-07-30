import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Admin-only chip on catalog tool cards to add a new occurrence to inventory.
class ToolCollectBadge extends StatelessWidget {
  const ToolCollectBadge({
    super.key,
    this.onPressed,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

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
        child: busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cardTheme.cardTextPrimary.withValues(alpha: 0.78),
                ),
              )
            : Text(
                'Add',
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

    if (onPressed == null || busy) return chip;

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
