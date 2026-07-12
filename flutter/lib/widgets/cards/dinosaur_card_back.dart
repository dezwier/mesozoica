import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_fossil_list.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({
    super.key,
    required this.dinosaur,
    this.showArticleButton = true,
  });

  final DinosaurSummary dinosaur;
  final bool showArticleButton;

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
                  showArticleButton: showArticleButton,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 90,
                  child: GeologicTimeline(
                    birth: dinosaur.birth,
                    death: dinosaur.death,
                    axis: GeologicTimelineAxis.horizontal,
                    scale: _contentScale,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CLADOGRAM',
                                style: cardTheme.sectionLabelStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: CladogramStrip(
                                    nodes: nodes,
                                    scale: _contentScale,
                                    centered: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 55,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FOSSIL RECORD',
                                style: cardTheme.sectionLabelStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: DinosaurCardFossilList(
                                  dinosaurId: dinosaur.id,
                                ),
                              ),
                            ],
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
