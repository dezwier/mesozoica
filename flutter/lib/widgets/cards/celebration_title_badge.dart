import 'package:flutter/material.dart';

import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';

/// Compact plaque for celebration headlines ("Site discovered!", etc.).
///
/// Same chrome family as the XP award badge / HUD bar, but flatter and more
/// label-like — neutral cream type on soft leather, no shouty display size.
class CelebrationTitleBadge extends StatelessWidget {
  const CelebrationTitleBadge({
    super.key,
    required this.title,
  });

  final String title;

  static const _radius = 10.0;

  @override
  Widget build(BuildContext context) {
    final label = _formatTitle(title);
    return DecoratedBox(
      decoration: MapChromeDecorations.leatherPanel(
        borderRadius: BorderRadius.circular(_radius),
        soft: true,
        compact: true,
      ).copyWith(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: MapChromeTheme.serifFont,
                color: MapChromeTheme.cream.withValues(alpha: 0.94),
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.05,
                letterSpacing: 0.85,
                decoration: TextDecoration.none,
                shadows: const [
                  Shadow(
                    color: Color(0x88000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 36,
              height: 1.25,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  gradient: LinearGradient(
                    colors: [
                      MapChromeTheme.brassMid.withValues(alpha: 0.0),
                      MapChromeTheme.mutedGold.withValues(alpha: 0.75),
                      MapChromeTheme.brassMid.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Softens shouty punctuation and trims whitespace for a calmer plaque.
  static String _formatTitle(String raw) {
    var t = raw.trim();
    while (t.endsWith('!')) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    return t;
  }
}
