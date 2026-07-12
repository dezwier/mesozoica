import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'dino_fact_row.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({super.key, required this.fossil});

  final FossilSummary fossil;

  static const _icon = 'assets/images/cards/icons/location.svg';

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: DinoCardTheme.of(context).cardBackground),
          Opacity(
            opacity: 0.1,
            child: FossilCardImage(imageUrl: fossil.mainImageUrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FossilCardHeader(
                  fossil: fossil,
                  titleFontSize: 24,
                  centered: true,
                  useFrontTitleStyle: true,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in _storedFields(fossil))
                          DinoFactRow(
                            iconAsset: _icon,
                            label: field.label,
                            value: field.value,
                            compact: true,
                            maxValueLines: field.maxValueLines,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoredField {
  const _StoredField({
    required this.label,
    required this.value,
    this.maxValueLines = 2,
  });

  final String label;
  final String value;
  final int maxValueLines;
}

List<_StoredField> _storedFields(FossilSummary fossil) {
  return [
    _StoredField(label: 'Occurrence no', value: '${fossil.id}'),
    _StoredField(label: 'Dinosaur', value: displayFactValue(fossil.dinosaurName)),
    _StoredField(label: 'Family', value: displayFactValue(fossil.family)),
    _StoredField(label: 'Country code', value: displayFactValue(fossil.countryCode)),
    _StoredField(label: 'State', value: displayFactValue(fossil.state)),
    _StoredField(
      label: 'Geological formation',
      value: displayFactValue(fossil.geologicalFormation),
    ),
    _StoredField(label: 'Latitude', value: _displayDecimal(fossil.latitude, decimals: 6)),
    _StoredField(label: 'Longitude', value: _displayDecimal(fossil.longitude, decimals: 6)),
    _StoredField(label: 'Early interval', value: displayFactValue(fossil.earlyInterval)),
    _StoredField(label: 'Min age (Ma)', value: _displayDecimal(fossil.minAgeMa)),
    _StoredField(label: 'Max age (Ma)', value: _displayDecimal(fossil.maxAgeMa)),
    _StoredField(label: 'Collection name', value: displayFactValue(fossil.collectionName)),
    _StoredField(label: 'Collection dates', value: displayFactValue(fossil.collectionDates)),
    _StoredField(
      label: 'Stratigraphy comments',
      value: displayFactValue(fossil.stratcomments),
      maxValueLines: 4,
    ),
    _StoredField(
      label: 'Lithology',
      value: displayFactValue(fossil.lithdescript),
      maxValueLines: 4,
    ),
    _StoredField(
      label: 'Collectors',
      value: displayFactValue(fossil.collectors),
      maxValueLines: 3,
    ),
    _StoredField(label: 'Museum', value: displayFactValue(fossil.museum)),
    _StoredField(label: 'Preservation mode', value: displayFactValue(fossil.presMode)),
    _StoredField(
      label: 'Preservation quality',
      value: displayFactValue(fossil.preservationQuality),
    ),
    _StoredField(label: 'Abundance value', value: _displayInt(fossil.abundValue)),
    _StoredField(label: 'Abundance unit', value: displayFactValue(fossil.abundUnit)),
  ];
}

String _displayDecimal(double? value, {int decimals = 2}) {
  if (value == null) return '—';
  return value.toStringAsFixed(decimals);
}

String _displayInt(int? value) {
  if (value == null) return '—';
  return '$value';
}
