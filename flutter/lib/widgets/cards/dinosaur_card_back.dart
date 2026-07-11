import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_header.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  static const _contentScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final nodes = dinosaur.cladogramNodes();
    final description = dinosaur.shortDescription != null &&
            dinosaur.shortDescription!.trim().isNotEmpty
        ? dinosaur.shortDescription!.trim()
        : '—';

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: ColoredBox(
        color: cardTheme.cardBackground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DinosaurCardHeader(
                dinosaur: dinosaur,
                titleFontSize: 22,
                subtitleFontSize: 13,
                centered: true,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: cardTheme.bodyStyle(fontSize: 13),
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
              const SizedBox(height: 0),
              Expanded(
                child: CladogramStrip(
                  nodes: nodes,
                  scale: _contentScale,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
