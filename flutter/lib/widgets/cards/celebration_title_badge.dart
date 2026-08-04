import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/xp_award_controller.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';
import '../xp/xp_skill_avatar.dart';

/// Sentence-style headlines for celebration plaques.
abstract final class CelebrationTitles {
  static const siteDiscovered = 'You discovered an excavation site!';
  static const siteDocumented =
      'You documented what there is to know about this excavation site';
  static const siteIdentified = 'You identified this excavation site!';
  static const fossilDiscovered = 'You discovered a fossil!';
}

/// Compact plaque for celebration headlines.
///
/// Big-event XP is **embedded here** (not as a floating badge): optional
/// [xpAwards] rows under the title rule show skill avatar + source + amount
/// for every XP line claimed for this celebration. XP rows share a left edge
/// while the block stays centered in the wider plaque.
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
    final hasXp = xpAwards.isNotEmpty;
    final screenW = MediaQuery.sizeOf(context).width;
    // Wider than the old shrink-wrap plaque so sentence titles + XP fit.
    final plaqueWidth = math.min(screenW - 32, 400.0);

    return SizedBox(
      width: plaqueWidth,
      child: DecoratedBox(
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title.trim(),
                textAlign: TextAlign.center,
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: MapChromeTheme.serifFont,
                  color: MapChromeTheme.cream.withValues(alpha: 0.94),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: 0.35,
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
              const SizedBox(height: 8),
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
                const SizedBox(height: 12),
                // IntrinsicWidth + start alignment: rows share a left edge;
                // Center keeps the XP block centered in the plaque.
                Center(
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < xpAwards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _CelebrationXpRow(award: xpAwards[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
        const SizedBox(width: 10),
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
