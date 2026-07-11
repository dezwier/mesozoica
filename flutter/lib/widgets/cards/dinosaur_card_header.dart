import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';

class DinosaurCardHeader extends StatelessWidget {
  const DinosaurCardHeader({
    super.key,
    required this.dinosaur,
    this.titleFontSize = 18,
    this.subtitleFontSize = 11,
  });

  final DinosaurSummary dinosaur;
  final double titleFontSize;
  final double subtitleFontSize;

  String? _subtitle() {
    final title = dinosaur.wikipediaTitle.trim();
    if (title.isEmpty || title.toLowerCase() == dinosaur.name.toLowerCase()) {
      return null;
    }
    return title.replaceAll('_', ' ').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dinosaur.name.toUpperCase(),
          style: DinoCardTheme.titleStyle(fontSize: titleFontSize),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: DinoCardTheme.subtitleStyle(fontSize: subtitleFontSize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
