import 'package:flutter/material.dart';

import '../../theme/map_chrome_theme.dart';
import '../profile/profile_skill_icons.dart';

/// Brass-framed skill icon used on XP badges and celebration plaque rows.
class XpSkillAvatar extends StatelessWidget {
  const XpSkillAvatar({
    super.key,
    required this.skillId,
    this.size = 38,
  });

  final String skillId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * (8 / 38);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
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
        borderRadius: BorderRadius.circular(radius - 1),
        child: Padding(
          padding: EdgeInsets.all(size * (3 / 38)),
          child: SkillIcon(skillId: skillId, size: size - size * (8 / 38)),
        ),
      ),
    );
  }
}
