import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../utils/display_text.dart';
import 'card_fact_badge.dart';

/// Attribute panel for the dinosaur card front overlay.
class DinosaurCardEdgeFacts extends StatelessWidget {
  const DinosaurCardEdgeFacts({
    super.key,
    required this.dinosaur,
    this.includeLocation = true,
  });

  final DinosaurSummary dinosaur;
  final bool includeLocation;

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  @override
  Widget build(BuildContext context) {
    final facts = <CardFactEntry>[
      CardFactEntry(
        iconAsset: 'assets/images/cards/icons/period.svg',
        label: 'Period',
        value: displayFactValue(
          dinosaur.displayPeriodName == '—' ? null : dinosaur.displayPeriodName,
        ),
      ),
      CardFactEntry(
        iconAsset: 'assets/images/cards/icons/diet.svg',
        label: 'Diet',
        value: displayFactValue(dinosaur.dietType),
      ),
      if (includeLocation)
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Location',
          value: displayFactValue(dinosaur.location),
          maxValueLines: 4,
        ),
      CardFactEntry(
        iconAsset: 'assets/images/cards/icons/mass.svg',
        label: 'Mass',
        value: _orDash(dinosaur.mass),
      ),
      CardFactEntry(
        iconAsset: 'assets/images/cards/icons/length.svg',
        label: 'Length',
        value: _orDash(dinosaur.length),
      ),
    ];

    return CardFactPanel(
      columns: includeLocation ? 3 : 2,
      layout: CardFactPanelLayout.columnGrid,
      facts: facts,
    );
  }
}
