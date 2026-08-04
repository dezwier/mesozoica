import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../controllers/xp_award_controller.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';
import '../profile/profile_skill_icons.dart';

/// XP-earned badge: skill avatar + XP source label + "+N XP".
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
            _SkillAvatar(skillId: award.skillId),
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

class _SkillAvatar extends StatelessWidget {
  const _SkillAvatar({required this.skillId});

  final String skillId;

  static const double _size = 38;
  static const double _radius = 8;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MapChromeTheme.leatherSoftHighlight,
            MapChromeTheme.dialFaceDeep,
          ],
        ),
        border: Border.all(
          color: MapChromeTheme.brassRim.withValues(alpha: 0.65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius - 1),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: SkillIcon(skillId: skillId, size: _size - 8),
        ),
      ),
    );
  }
}
