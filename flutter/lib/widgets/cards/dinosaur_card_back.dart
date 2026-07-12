import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_facts.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  static const _contentScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final nodes = dinosaur.cladogramNodes();

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cardTheme.cardBackground),
          Opacity(
            opacity: 0.1,
            child: DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 30, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DinosaurCardHeader(
                  dinosaur: dinosaur,
                  titleFontSize: 28,
                  subtitleFontSize: 13,
                  centered: true,
                  useFrontTitleStyle: true,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 102,
                  child: GeologicTimeline(
                    birth: dinosaur.birth,
                    death: dinosaur.death,
                    axis: GeologicTimelineAxis.horizontal,
                    scale: _contentScale,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: DinosaurCardFacts(
                              dinosaur: dinosaur,
                              compact: true,
                              vertical: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: CladogramStrip(
                            nodes: nodes,
                            scale: _contentScale,
                            centered: false,
                          ),
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
