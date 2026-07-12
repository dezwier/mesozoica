import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';

class DinosaurCardHeader extends StatelessWidget {
  const DinosaurCardHeader({
    super.key,
    required this.dinosaur,
    this.titleFontSize = 18,
    this.subtitleFontSize = 11,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.showArticleButton = false,
  });

  final DinosaurSummary dinosaur;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool showArticleButton;

  String? _subtitle() {
    final title = dinosaur.wikipediaTitle.trim();
    if (title.isEmpty || title.toLowerCase() == dinosaur.name.toLowerCase()) {
      return null;
    }
    return title.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final subtitle = _subtitle();

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                dinosaur.name,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: useFrontTitleStyle
                    ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
                    : cardTheme.titleStyle(fontSize: titleFontSize),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showArticleButton) ...[
              const SizedBox(width: 2),
              IconButton(
                onPressed: () => DinosaurArticleDrawer.show(
                  context,
                  dinosaur: dinosaur,
                ),
                icon: const Icon(Icons.info_outline, size: 16),
                color: cardTheme.cardTextMuted,
                tooltip: 'Read article',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
              ),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: cardTheme.subtitleStyle(fontSize: subtitleFontSize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
