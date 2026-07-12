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

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final description = fossil.description != null &&
            fossil.description!.trim().isNotEmpty
        ? fossil.description!.trim()
        : '—';

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cardTheme.cardBackground),
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
                        _FactSection(
                          rows: [
                            _FactSpec(
                              icon: 'assets/images/cards/icons/diet.svg',
                              label: 'Genus',
                              value: displayFactValue(fossil.dinosaurName),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/diet.svg',
                              label: 'Family',
                              value: displayFactValue(fossil.family),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _FactSection(
                          rows: [
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'Country',
                              value: displayFactValue(fossil.countryCode),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'State',
                              value: displayFactValue(fossil.state),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'Formation',
                              value: displayFactValue(fossil.geologicalFormation),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'Site',
                              value: displayFactValue(fossil.collectionName),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'Coordinates',
                              value: fossil.displayCoordinates,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _FactSection(
                          rows: [
                            _FactSpec(
                              icon: 'assets/images/cards/icons/period.svg',
                              label: 'Interval',
                              value: displayFactValue(fossil.earlyInterval),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/period.svg',
                              label: 'Age',
                              value: fossil.displayAgeRange,
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/period.svg',
                              label: 'Rock type',
                              value: displayFactValue(fossil.lithdescript),
                              maxValueLines: 4,
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/period.svg',
                              label: 'Stratigraphy',
                              value: displayFactValue(fossil.stratcomments),
                              maxValueLines: 4,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: cardTheme.bodyStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _FactSection(
                          rows: [
                            _FactSpec(
                              icon: 'assets/images/cards/icons/period.svg',
                              label: 'Collection dates',
                              value: displayFactValue(fossil.collectionDates),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/diet.svg',
                              label: 'Collectors',
                              value: displayFactValue(fossil.collectors),
                              maxValueLines: 3,
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/location.svg',
                              label: 'Museum',
                              value: displayFactValue(fossil.museum),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _FactSection(
                          rows: [
                            _FactSpec(
                              icon: 'assets/images/cards/icons/mass.svg',
                              label: 'Preservation mode',
                              value: displayFactValue(fossil.presMode),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/length.svg',
                              label: 'Quality',
                              value: displayFactValue(fossil.preservationQuality),
                            ),
                            _FactSpec(
                              icon: 'assets/images/cards/icons/mass.svg',
                              label: 'Abundance',
                              value: fossil.displayAbundance,
                            ),
                          ],
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

class _FactSpec {
  const _FactSpec({
    required this.icon,
    required this.label,
    required this.value,
    this.maxValueLines = 2,
  });

  final String icon;
  final String label;
  final String value;
  final int maxValueLines;
}

class _FactSection extends StatelessWidget {
  const _FactSection({required this.rows});

  final List<_FactSpec> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in rows)
          DinoFactRow(
            iconAsset: row.icon,
            label: row.label,
            value: row.value,
            compact: true,
            maxValueLines: row.maxValueLines,
          ),
      ],
    );
  }
}
