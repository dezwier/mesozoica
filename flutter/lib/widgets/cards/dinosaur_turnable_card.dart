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
  });

  final DinosaurSummary dinosaur;

  @override
  Widget build(BuildContext context) {
    return TurnableYAxisCard(
      resetIdentity: dinosaur.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: DinoCardTheme.chromeDecoration,
      front: DinosaurCardFront(dinosaur: dinosaur),
      back: DinosaurCardBack(dinosaur: dinosaur),
    );
  }
}
