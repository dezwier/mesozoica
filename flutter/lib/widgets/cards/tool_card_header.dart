import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
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
    this.showRarityStars = false,
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
  /// Filled rarity stars below the scientific subtitle (back side).
  final bool showRarityStars;
  final double skillBadgeSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = overlayOnImage
        ? cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize)
        : cardTheme.titleStyle(fontSize: titleFontSize);
    final subtitleStyle = overlayOnImage
        ? cardTheme.frontOverlaySubtitleStyle(fontSize: subtitleFontSize)
        : cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
            color: cardTheme.cardTextMuted,
            fontWeight: FontWeight.w500,
          );

    final subtitleText = subtitleOverride ??
        (showScientificSubtitle || showRarityStars
            ? tool.displayScientificTool
            : null);
    final hasSubtitle = subtitleText != null && subtitleText.isNotEmpty;
    final rarity = showRarityStars ? tool.rarity.clamp(0, 5) : 0;
    final starColor = overlayOnImage
        ? const Color(0xFFE6C35C)
        : cardTheme.cardAccent;

    // With a skill badge, title/subtitle center in the remaining width.
    final centerInSpace = showSkillBadge || centered;

    final titleBlock = Column(
      crossAxisAlignment:
          centerInSpace ? CrossAxisAlignment.center : CrossAxisAlignment.start,
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
        if (rarity > 0) ...[
          const SizedBox(height: 4),
          _RarityStars(
            rarity: rarity,
            starSize: (subtitleStyle.fontSize ?? 10) + 3,
            color: starColor,
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
        SkillIcon(
          skillId: skillId,
          size: skillBadgeSize,
          circular: true,
        ),
      ],
    );
  }
}

class _RarityStars extends StatelessWidget {
  const _RarityStars({
    required this.rarity,
    required this.starSize,
    required this.color,
  });

  final int rarity;
  final double starSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rarity; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 1),
            child: Icon(
              Icons.star_rounded,
              size: starSize,
              color: color,
              shadows: const [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
