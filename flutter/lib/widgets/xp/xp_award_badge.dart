import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/xp_award_controller.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';
import 'xp_skill_avatar.dart';

/// XP-earned **badge** for small / ongoing events (not celebrations).
///
/// Skill avatar + XP source label + "+N XP". Big-event XP is embedded in
/// celebration plaques instead — see `xp_source_labels.dart`.
class XpAwardBadge extends StatelessWidget {
  const XpAwardBadge({
    super.key,
    required this.award,
  });

  final XpAward award;

  static final _xpFormat = NumberFormat('#,###');
  static const _radius = 11.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: MapChromeDecorations.leatherPanel(
        borderRadius: BorderRadius.circular(_radius),
        soft: true,
      ).copyWith(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            XpSkillAvatar(skillId: award.skillId),
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
                    color: MapChromeTheme.cream.withValues(alpha: 0.92),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: 0.2,
                    decoration: TextDecoration.none,
                    shadows: const [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+${_xpFormat.format(award.amount)} XP',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: MapChromeTheme.serifFont,
                    color: MapChromeTheme.mutedGold,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    letterSpacing: 0.35,
                    decoration: TextDecoration.none,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
