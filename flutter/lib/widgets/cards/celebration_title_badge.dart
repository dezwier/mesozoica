import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/xp_award_controller.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';
import '../xp/xp_skill_avatar.dart';

/// Compact plaque for celebration headlines ("Site discovered!", etc.).
///
/// Big-event XP is **embedded here** (not as a floating badge): optional
/// [xpAwards] rows under the title rule show skill avatar + source + amount
/// for every XP line claimed for this celebration.
///
/// Same chrome family as the XP award badge / HUD bar, but flatter and more
/// label-like — neutral cream type on soft leather, no shouty display size.
class CelebrationTitleBadge extends StatelessWidget {
  const CelebrationTitleBadge({
    super.key,
    required this.title,
    this.xpAwards = const [],
  });

  final String title;

  /// XP rows claimed for this celebration (source + amount + skill avatar).
  final List<XpAward> xpAwards;

  static final _xpFormat = NumberFormat('#,###');
  static const _radius = 10.0;

  @override
  Widget build(BuildContext context) {
    final label = _formatTitle(title);
    final hasXp = xpAwards.isNotEmpty;
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
        padding: EdgeInsets.fromLTRB(hasXp ? 12 : 16, 9, hasXp ? 14 : 16, 9),
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
            if (hasXp) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < xpAwards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _CelebrationXpRow(award: xpAwards[i]),
              ],
            ],
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

class _CelebrationXpRow extends StatelessWidget {
  const _CelebrationXpRow({required this.award});

  final XpAward award;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        XpSkillAvatar(skillId: award.skillId, size: 28),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              award.sourceLabel,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: MapChromeTheme.serifFont,
                color: MapChromeTheme.cream.withValues(alpha: 0.88),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.05,
                letterSpacing: 0.15,
                decoration: TextDecoration.none,
                shadows: const [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '+${CelebrationTitleBadge._xpFormat.format(award.amount)} XP',
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontFamily: MapChromeTheme.serifFont,
                color: MapChromeTheme.mutedGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: 0.3,
                decoration: TextDecoration.none,
                shadows: [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
