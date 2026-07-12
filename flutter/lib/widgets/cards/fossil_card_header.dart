import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';

class FossilCardHeader extends StatelessWidget {
  const FossilCardHeader({
    super.key,
    required this.fossil,
    this.titleFontSize = 18,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.wrapTitle = false,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool wrapTitle;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          fossil.displayTitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: useFrontTitleStyle
              ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
              : cardTheme.titleStyle(fontSize: titleFontSize),
          maxLines: wrapTitle ? null : 2,
          overflow: wrapTitle ? TextOverflow.visible : TextOverflow.ellipsis,
          softWrap: true,
        ),
      ],
    );
  }
}
