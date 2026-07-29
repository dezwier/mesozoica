import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_back.dart';
import 'dinosaur_card_front.dart';
import 'turnable_y_axis_card.dart';

class DinosaurTurnableCard extends StatelessWidget {
  const DinosaurTurnableCard({
    super.key,
    required this.dinosaur,
    this.showFrontFacts = true,
    this.showArticleButton,
    this.turnable = true,
    this.enableDragFlip = true,
    this.outerPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fixedFaceHeight,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
  });

  final DinosaurSummary dinosaur;
  final bool showFrontFacts;
  final bool? showArticleButton;
  final bool turnable;
  final bool enableDragFlip;
  final EdgeInsets outerPadding;
  final double? fixedFaceHeight;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    return TurnableYAxisCard(
      resetIdentity: dinosaur.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: outerPadding,
      fixedFaceHeight: fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: turnable,
      enableDragFlip: enableDragFlip,
      front: DinosaurCardFront(
        dinosaur: dinosaur,
        showFacts: showFrontFacts,
        titleFontSize: titleFontSize,
        subtitleFontSize: subtitleFontSize,
        overlayHeightFactor: overlayHeightFactor,
      ),
      back: DinosaurCardBack(
        dinosaur: dinosaur,
        showArticleButton: showArticleButton ?? showFrontFacts,
        titleFontSize: titleFontSize,
        subtitleFontSize: subtitleFontSize,
      ),
    );
  }
}
