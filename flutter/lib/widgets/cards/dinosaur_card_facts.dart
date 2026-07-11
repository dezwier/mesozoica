import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import 'dino_fact_row.dart';

class DinosaurCardFacts extends StatelessWidget {
  const DinosaurCardFacts({
    super.key,
    required this.dinosaur,
    this.compact = false,
  });

  final DinosaurSummary dinosaur;
  final bool compact;

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Location',
          value: _orDash(dinosaur.location),
          compact: compact,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Time Period',
          value: dinosaur.displayPeriod,
          compact: compact,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/diet.svg',
          label: 'Diet',
          value: _orDash(dinosaur.dietType),
          compact: compact,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/length.svg',
          label: 'Length',
          value: _orDash(dinosaur.length),
          compact: compact,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/mass.svg',
          label: 'Mass',
          value: _orDash(dinosaur.mass),
          compact: compact,
        ),
      ],
    );
  }
}
