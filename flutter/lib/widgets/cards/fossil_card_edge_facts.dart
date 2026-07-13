import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../utils/display_text.dart';
import 'card_fact_badge.dart';

/// Attribute panel for the fossil card front overlay.
class FossilCardEdgeFacts extends StatelessWidget {
  const FossilCardEdgeFacts({
    super.key,
    required this.fossil,
  });

  final FossilSummary fossil;

  @override
  Widget build(BuildContext context) {
    return CardFactPanel(
      columns: 3,
      layout: CardFactPanelLayout.columnGrid,
      facts: [
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/diet.svg',
          label: 'Dinosaur',
          value: displayFactValue(fossil.dinosaurName),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/mass.svg',
          label: 'Rock type',
          value: displayFactValue(
            fossil.displayRockType == '—' ? null : fossil.displayRockType,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Period',
          value: displayFactValue(
            fossil.displayPeriod == '—' ? null : fossil.displayPeriod,
          ),
          maxValueLines: 3,
        ),
      ],
    );
  }
}
