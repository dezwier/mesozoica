import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';
import 'card_section_panel.dart';
import 'tool_card_image.dart';

class ToolCardBack extends StatelessWidget {
  const ToolCardBack({
    super.key,
    required this.tool,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ToolCardImage(imageUrl: tool.mainImageUrl),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CardAdaptiveTitleText(
                  text: tool.scientificTool,
                  style: cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 96,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardSectionPanel(
                  label: 'Category',
                  child: Text(
                    tool.displayCategory,
                    style: cardTheme.bodyStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                CardSectionPanel(
                  label: 'Rarity',
                  child: _RarityRow(rarity: tool.rarity),
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
