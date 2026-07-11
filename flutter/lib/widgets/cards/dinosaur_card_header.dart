import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';

class DinosaurCardHeader extends StatelessWidget {
  const DinosaurCardHeader({
    super.key,
    required this.dinosaur,
    this.titleFontSize = 18,
    this.subtitleFontSize = 11,
    this.centered = false,
    this.useFrontTitleStyle = false,
  });

  final DinosaurSummary dinosaur;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;

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
        Text(
          dinosaur.name,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: useFrontTitleStyle
              ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
              : cardTheme.titleStyle(fontSize: titleFontSize),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
