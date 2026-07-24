import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import '../common/chrome_action_button.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'tool_card_header.dart';
import 'tool_card_image.dart';

class ToolCardBack extends StatelessWidget {
  const ToolCardBack({
    super.key,
    required this.tool,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.onAction,
    this.onInfo,
    this.statsChild,
    this.ongoingChild,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final VoidCallback? onAction;
  final VoidCallback? onInfo;
  /// Replaces the Rarity panel when non-null (e.g. deploy stats).
  final Widget? statsChild;
  /// Optional ongoing-mission panel below stats.
  final Widget? ongoingChild;

  static const double _actionHeight = 44;
  static const double _actionGap = 6;

  @override
  Widget build(BuildContext context) {
    final actionEnabled = tool.isOwned && onAction != null;
    final middle = statsChild ??
        CardSectionPanel(
          label: 'Rarity',
          child: _RarityRow(rarity: tool.rarity),
        );

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(
            image: ToolCardImage(imageUrl: tool.mainImageUrl),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: ToolCardHeader(
              tool: tool,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
              subtitleOverride: tool.categoryWithScientific,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 108,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                middle,
                if (ongoingChild != null) ...[
                  const SizedBox(height: 8),
                  ongoingChild!,
                ],
                const Spacer(),
                SizedBox(
                  height: _actionHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ChromeActionButton(
                          label: tool.action,
                          onPressed: actionEnabled ? onAction : null,
                        ),
                      ),
                      const SizedBox(width: _actionGap),
                      Expanded(
                        child: ChromeActionButton(
                          label: 'Info',
                          onPressed: onInfo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RarityRow extends StatelessWidget {
  const _RarityRow({required this.rarity});

  final int rarity;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final clamped = rarity.clamp(1, 5);

    return Row(
      children: [
        ...List.generate(5, (index) {
          final filled = index < clamped;
          return Padding(
            padding: EdgeInsets.only(right: index == 4 ? 0 : 4),
            child: Icon(
              filled ? Icons.star : Icons.star_border,
              size: 18,
              color: filled ? cardTheme.cardAccent : cardTheme.cardTextMuted,
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          '$clamped/5',
          style: cardTheme.bodyStyle(fontSize: 13),
        ),
      ],
    );
  }
}
