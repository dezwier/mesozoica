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
    this.centered = false,
    this.maxValueLines = 2,
  });

  final String iconAsset;
  final String label;
  final String value;
  final bool compact;
  final bool centered;
  final int maxValueLines;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final iconSize = compact ? 14.0 : 18.0;
    final labelSize = compact ? 8.0 : 10.0;
    final valueSize = compact ? 11.0 : 13.0;
    final rowPadding = compact ? 10.0 : 8.0;
    final valueLines = compact ? 2 : maxValueLines;

    return Padding(
      padding: EdgeInsets.only(bottom: rowPadding),
      child: Row(
        mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            iconAsset,
            width: iconSize,
            height: iconSize,
          ),
          const SizedBox(width: 10),
          if (centered)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: cardTheme.statLabelStyle(fontSize: labelSize),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: cardTheme.statValueStyle(fontSize: valueSize),
                  maxLines: valueLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: cardTheme.statLabelStyle(fontSize: labelSize),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: cardTheme.statValueStyle(fontSize: valueSize),
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
