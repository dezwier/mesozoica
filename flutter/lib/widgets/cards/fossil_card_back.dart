import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import '../fossil/fossil_record_drawer.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'fossil_card_edge_facts.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';
import 'fossil_related_thumbs.dart';
import 'geologic_timeline.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({
    super.key,
    required this.fossil,
    this.showRecordButton = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final FossilSummary fossil;
  final bool showRecordButton;
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
          CardBackBackdrop(
            image: FossilCardImage(imageUrl: fossil.mainImageUrl),
          ),
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
          if (showRecordButton)
            Positioned(
              top: 14,
              right: 10,
              child: IconButton(
                onPressed: () => FossilRecordDrawer.show(
                  context,
                  fossil: fossil,
                ),
                icon: const Icon(Icons.info_outline, size: 18),
                color: const Color(0xE6F5F0E8),
                tooltip: 'Record details',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
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
                FossilCardEdgeFacts(fossil: fossil),
                const SizedBox(height: 10),
                Expanded(
                  child: FossilRelatedThumbs(fossil: fossil),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
