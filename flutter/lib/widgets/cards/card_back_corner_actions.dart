import 'package:flutter/material.dart';

/// Bottom-right row of card-back icon actions (wiki + history).
class CardBackCornerActions extends StatelessWidget {
  const CardBackCornerActions({super.key, this.wiki, required this.onHistory});

  /// Optional wiki / record / info action to the left of history.
  final VoidCallback? wiki;
  final VoidCallback onHistory;

  static const _iconColor = Color(0xE6F5F0E8);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 10,
      bottom: 10,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wiki != null)
                IconButton(
                  onPressed: wiki,
                  icon: const Icon(Icons.info_outline, size: 18),
                  color: _iconColor,
                  tooltip: 'Details',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              IconButton(
                onPressed: onHistory,
                icon: const Icon(Icons.history, size: 18),
                color: _iconColor,
                tooltip: 'History',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
