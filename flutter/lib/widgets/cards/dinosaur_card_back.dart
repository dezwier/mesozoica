import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'card_section_panel.dart';
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
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final DinosaurSummary dinosaur;
  final bool showArticleButton;
  final double titleFontSize;
  final double subtitleFontSize;

  static const _contentScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final nodes = dinosaur.cladogramNodes();

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: DinosaurCardHeader(
              dinosaur: dinosaur,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
            ),
          ),
          if (showArticleButton)
            Positioned(
              top: 14,
              right: 10,
              child: IconButton(
                onPressed: () => DinosaurArticleDrawer.show(
                  context,
                  dinosaur: dinosaur,
                ),
                icon: const Icon(Icons.info_outline, size: 18),
                color: const Color(0xE6F5F0E8),
                tooltip: 'Read article',
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
                  label: 'Time',
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: SizedBox(
                    height: 78,
                    child: GeologicTimeline(
                      birth: dinosaur.birth,
                      death: dinosaur.death,
                      axis: GeologicTimelineAxis.horizontal,
                      scale: _contentScale,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 55,
                        child: CardSectionPanel(
                          label: 'Fossil record',
                          expandChild: true,
                          child: DinosaurCardFossilList(
                            dinosaurId: dinosaur.id,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 45,
                        child: CardSectionPanel(
                          label: 'Cladogram',
                          expandChild: true,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
