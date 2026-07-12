import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'dino_fact_row.dart';

/// Subtle vertical attribute strip for the card front right edge.
class DinosaurCardEdgeFacts extends StatelessWidget {
  const DinosaurCardEdgeFacts({
    super.key,
    required this.dinosaur,
  });

  final DinosaurSummary dinosaur;

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            cardTheme.cardBackground.withValues(alpha: 0.84),
            cardTheme.cardBackground.withValues(alpha: 0.74),
            cardTheme.cardBackground.withValues(alpha: 0.50),
            cardTheme.cardBackground.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.38, 0.72, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/location.svg',
              label: 'Location',
              value: displayFactValue(dinosaur.location),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/period.svg',
              label: 'Period',
              value: displayFactValue(
                dinosaur.displayPeriodName == '—'
                    ? null
                    : dinosaur.displayPeriodName,
              ),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/diet.svg',
              label: 'Diet',
              value: displayFactValue(dinosaur.dietType),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/length.svg',
              label: 'Length',
              value: _orDash(dinosaur.length),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/mass.svg',
              label: 'Mass',
              value: _orDash(dinosaur.mass),
              edge: true,
              rowPadding: 0,
            ),
          ],
        ),
      ),
    );
  }
}
