import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/profile.dart';
import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import '../profile/profile_skill_detail_sheet.dart';
import '../profile/profile_skill_icons.dart';
import 'card_adaptive_title_text.dart';

class ToolCardHeader extends StatelessWidget {
  const ToolCardHeader({
    super.key,
    required this.tool,
    this.titleFontSize = 18,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.overlayOnImage = false,
    this.showScientificSubtitle = false,
    this.subtitleOverride,
    this.showSkillBadge = false,
    this.skillBadgeSize = 44,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool overlayOnImage;
  final bool showScientificSubtitle;

  /// When set, shown as the subtitle instead of scientific name.
  final String? subtitleOverride;

  /// Top-right skill avatar (back side).
  final bool showSkillBadge;
  final double skillBadgeSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = overlayOnImage
        ? cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize)
        : cardTheme.titleStyle(fontSize: titleFontSize);
    final subtitleStyle = overlayOnImage
        ? cardTheme.frontOverlaySubtitleStyle(fontSize: subtitleFontSize)
        : cardTheme
              .subtitleStyle(fontSize: subtitleFontSize)
              .copyWith(
                color: cardTheme.cardTextMuted,
                fontWeight: FontWeight.w500,
              );

    final subtitleText =
        subtitleOverride ??
        (showScientificSubtitle ? tool.displayScientificTool : null);
    final hasSubtitle = subtitleText != null && subtitleText.isNotEmpty;

    // With a skill badge, title/subtitle center in the remaining width.
    final centerInSpace = showSkillBadge || centered;

    final titleBlock = Column(
      crossAxisAlignment: centerInSpace
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: CardAdaptiveTitleText(
            text: tool.name,
            style: titleStyle,
            textAlign: centerInSpace ? TextAlign.center : TextAlign.start,
          ),
        ),
        if (hasSubtitle) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: Text(
              subtitleText,
              textAlign: centerInSpace ? TextAlign.center : TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
        ],
      ],
    );

    final skillId = tool.skillId;
    if (!showSkillBadge || skillId == null) {
      return titleBlock;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openSkillSheet(context, tool),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: SkillIcon(
              skillId: skillId,
              size: skillBadgeSize,
              circular: true,
            ),
          ),
        ),
      ],
    );
  }

  static void _openSkillSheet(BuildContext context, ToolSummary tool) {
    final skillId = tool.skillId;
    if (skillId == null) return;

    final profile = context.read<AuthController>().currentUser;
    SkillState? skill;
    Map<String, int>? breakdown;
    if (profile != null) {
      for (final item in profile.skills) {
        if (item.id == skillId) {
          skill = item;
          break;
        }
      }
      breakdown = profile.skillBreakdown[skillId];
    }
    skill ??= SkillState(
      id: skillId,
      name: tool.displayCategory.isNotEmpty ? tool.displayCategory : skillId,
      xp: 0,
      level: 1,
      nextLevelXp: 0,
      xpToNext: 0,
      progress: 0,
    );

    showProfileSkillDetailSheet(context, skill: skill, breakdown: breakdown);
  }
}
