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
    this.edge = false,
    this.maxValueLines = 2,
    this.maxLines,
    this.wrapValue = false,
    this.rowPadding,
  });

  final String iconAsset;
  final String label;
  final String value;
  final bool compact;
  final bool centered;
  final bool edge;
  final int maxValueLines;
  final int? maxLines;
  final bool wrapValue;
  final double? rowPadding;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final iconSize = edge ? 13.0 : (compact ? 14.0 : 18.0);
    final labelSize = compact ? 8.0 : 10.0;
    final valueSize = edge ? 11.0 : (compact ? 11.0 : 13.0);
    final effectiveRowPadding =
        rowPadding ?? (edge ? 8.0 : (compact ? 10.0 : 8.0));
    final valueLines =
        maxLines ?? (edge ? 2 : (compact ? (centered ? 3 : 2) : maxValueLines));

    if (edge) {
      return Padding(
        padding: EdgeInsets.only(bottom: effectiveRowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: cardTheme
                    .statValueStyle(fontSize: valueSize)
                    .copyWith(
                      color: cardTheme.cardTextPrimary.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: valueLines,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            const SizedBox(width: 5),
            SvgPicture.asset(
              iconAsset,
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(
                cardTheme.cardTextPrimary.withValues(alpha: 0.65),
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: effectiveRowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(iconAsset, width: iconSize, height: iconSize),
          const SizedBox(width: 10),
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
                  maxLines: wrapValue ? null : valueLines,
                  overflow: wrapValue
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
