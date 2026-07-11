import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import 'dino_fact_row.dart';

class DinosaurCardFacts extends StatelessWidget {
  const DinosaurCardFacts({
    super.key,
    required this.dinosaur,
    this.compact = false,
    this.centered = false,
  });

  final DinosaurSummary dinosaur;
  final bool compact;
  final bool centered;

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  Widget _locationRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/location.svg',
        label: 'Location',
        value: _orDash(dinosaur.location),
        compact: compact,
        centered: centered,
      );

  Widget _periodRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/period.svg',
        label: 'Period',
        value: dinosaur.displayPeriodName,
        compact: compact,
        centered: centered,
      );

  Widget _dietRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/diet.svg',
        label: 'Diet',
        value: _orDash(dinosaur.dietType),
        compact: compact,
        centered: centered,
      );

  Widget _lengthRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/length.svg',
        label: 'Length',
        value: _orDash(dinosaur.length),
        compact: compact,
        centered: centered,
      );

  Widget _massRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/mass.svg',
        label: 'Mass',
        value: _orDash(dinosaur.mass),
        compact: compact,
        centered: centered,
      );

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final locationPeriodColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _locationRow(),
          _periodRow(),
        ],
      );
      final lengthMassColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lengthRow(),
          _massRow(),
        ],
      );
      final dietColumn = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dietRow(),
        ],
      );

      return SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: locationPeriodColumn),
            const SizedBox(width: 10),
            Expanded(child: lengthMassColumn),
            const SizedBox(width: 10),
            Expanded(child: dietColumn),
          ],
        ),
      );
    }

    return Column(
      children: [
        _locationRow(),
        _periodRow(),
        _dietRow(),
        _lengthRow(),
        _massRow(),
      ],
    );
  }
}
