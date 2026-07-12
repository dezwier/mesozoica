import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'fossil_card_back.dart';
import 'fossil_card_front.dart';
import 'turnable_y_axis_card.dart';

class FossilTurnableCard extends StatelessWidget {
  const FossilTurnableCard({
    super.key,
    required this.fossil,
    this.turnable = true,
    this.titleFontSize = 28,
    this.overlayHeightFactor = 0.35,
  });

  final FossilSummary fossil;
  final bool turnable;
  final double titleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    return TurnableYAxisCard(
      resetIdentity: fossil.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: turnable,
      front: FossilCardFront(
        fossil: fossil,
        titleFontSize: titleFontSize,
        overlayHeightFactor: overlayHeightFactor,
      ),
      back: FossilCardBack(fossil: fossil),
    );
  }
}
