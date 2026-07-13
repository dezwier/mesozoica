import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'card_section_panel.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';
import 'fossil_related_thumbs.dart';
import 'fossil_stored_fields_panel.dart';
import 'geologic_timeline.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({
    super.key,
    required this.fossil,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double subtitleFontSize;

  static const _contentScale = 1.15;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FossilCardImage(imageUrl: fossil.mainImageUrl),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: FossilCardHeader(
              fossil: fossil,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
              showOccurrenceSubtitle: true,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 72,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardSectionPanel(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: SizedBox(
                    height: 78,
                    child: GeologicTimeline.fromAgeRange(
                      minAgeMa: fossil.minAgeMa,
                      maxAgeMa: fossil.maxAgeMa,
                      axis: GeologicTimelineAxis.horizontal,
                      scale: _contentScale,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FossilRelatedThumbs(fossil: fossil),
                const SizedBox(height: 10),
                Expanded(
                  child: CardSectionPanel(
                    label: 'Record',
                    expandChild: true,
                    child: FossilStoredFieldsPanel(fields: fossil.storedFields),
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
