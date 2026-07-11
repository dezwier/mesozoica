import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/dino_card_theme.dart';

class DinoFactRow extends StatelessWidget {
  const DinoFactRow({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.value,
    this.compact = false,
    this.maxValueLines = 2,
  });

  final String iconAsset;
  final String label;
  final String value;
  final bool compact;
  final int maxValueLines;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 14.0 : 18.0;
    final labelSize = compact ? 8.0 : 10.0;
    final valueSize = compact ? 11.0 : 13.0;
    final rowPadding = compact ? 4.0 : 8.0;
    final valueLines = compact ? 1 : maxValueLines;

    return Padding(
      padding: EdgeInsets.only(bottom: rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            iconAsset,
            width: iconSize,
            height: iconSize,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: DinoCardTheme.statLabelStyle(fontSize: labelSize),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: DinoCardTheme.statValueStyle(fontSize: valueSize),
                  maxLines: valueLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
