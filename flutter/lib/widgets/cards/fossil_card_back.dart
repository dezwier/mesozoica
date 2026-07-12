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
                        _LocationBlock(fossil: fossil),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: cardTheme.bodyStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _CollectionBlock(fossil: fossil),
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

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.fossil});

  final FossilSummary fossil;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'State',
          value: displayFactValue(fossil.state),
          compact: true,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Formation',
          value: displayFactValue(fossil.geologicalFormation),
          compact: true,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Coordinates',
          value: fossil.displayCoordinates,
          compact: true,
        ),
      ],
    );
  }
}

class _CollectionBlock extends StatelessWidget {
  const _CollectionBlock({required this.fossil});

  final FossilSummary fossil;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Collection dates',
          value: displayFactValue(fossil.collectionDates),
          compact: true,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Comments',
          value: displayFactValue(fossil.stratcomments),
          compact: true,
          maxValueLines: 4,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/diet.svg',
          label: 'Collectors',
          value: displayFactValue(fossil.collectors),
          compact: true,
          maxValueLines: 3,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/mass.svg',
          label: 'Preservation mode',
          value: displayFactValue(fossil.presMode),
          compact: true,
        ),
        DinoFactRow(
          iconAsset: 'assets/images/cards/icons/length.svg',
          label: 'Quality',
          value: displayFactValue(fossil.preservationQuality),
          compact: true,
        ),
      ],
    );
  }
}
