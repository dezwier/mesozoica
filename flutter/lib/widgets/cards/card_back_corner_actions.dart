import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Gold circles on the hero: optional details, then history.
class CardBackCornerActions extends StatelessWidget {
  const CardBackCornerActions({super.key, this.wiki, required this.onHistory});

  /// Optional wiki / record / info action to the left of history.
  final VoidCallback? wiki;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wiki != null) ...[
            _GoldCircleButton(
              onPressed: wiki,
              icon: Icons.info_outline,
              tooltip: 'Details',
            ),
            const SizedBox(width: 6),
          ],
          _GoldCircleButton(
            onPressed: onHistory,
            icon: Icons.history,
            tooltip: 'History',
          ),
        ],
      ),
    );
  }
}

class _GoldCircleButton extends StatelessWidget {
  const _GoldCircleButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final gold = DinoCardTheme.of(context).cardAccent;
    return Material(
      color: const Color(0x8C120E0B),
      shape: CircleBorder(side: BorderSide(color: gold, width: 1.1)),
      elevation: 0,
      shadowColor: gold.withValues(alpha: 0.6),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: const Color(0xFFF6EFE4),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      ),
    );
  }
}
