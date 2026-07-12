import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../utils/display_text.dart';
import 'dino_fact_row.dart';

class DinosaurCardFacts extends StatelessWidget {
  const DinosaurCardFacts({
    super.key,
    required this.dinosaur,
    this.compact = false,
    this.vertical = false,
    this.centered = false,
  });

  final DinosaurSummary dinosaur;
  final bool compact;
  final bool vertical;
  final bool centered;

  double? get _rowPadding => vertical ? 22 : null;

  Widget _locationRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/location.svg',
        label: 'Location',
        value: displayFactValue(dinosaur.location),
        compact: compact,
        centered: centered,
        rowPadding: _rowPadding,
        maxLines: compact && centered ? 5 : null,
      );

  Widget _periodRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/period.svg',
        label: 'Period',
        value: displayFactValue(
          dinosaur.displayPeriodName == '—' ? null : dinosaur.displayPeriodName,
        ),
        compact: compact,
        centered: centered,
        rowPadding: _rowPadding,
      );

  Widget _dietRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/diet.svg',
        label: 'Diet',
        value: displayFactValue(dinosaur.dietType),
        compact: compact,
        centered: centered,
        rowPadding: _rowPadding,
      );

  String _orDash(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : '—';

  Widget _lengthRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/length.svg',
        label: 'Length',
        value: _orDash(dinosaur.length),
        compact: compact,
        centered: centered,
        rowPadding: _rowPadding,
      );

  Widget _massRow() => DinoFactRow(
        iconAsset: 'assets/images/cards/icons/mass.svg',
        label: 'Mass',
        value: _orDash(dinosaur.mass),
        compact: compact,
        centered: centered,
        rowPadding: _rowPadding,
      );

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _locationRow(),
          _periodRow(),
          _dietRow(),
          _lengthRow(),
          _massRow(),
        ],
      );
    }

    if (compact) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dietRow(),
                  _lengthRow(),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _periodRow(),
                  _massRow(),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _locationRow(),
                ],
              ),
            ),
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
