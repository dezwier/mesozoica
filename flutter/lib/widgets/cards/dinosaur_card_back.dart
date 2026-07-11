import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_header.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  @override
  Widget build(BuildContext context) {
    final nodes = dinosaur.cladogramNodes();
    final description = dinosaur.shortDescription != null &&
            dinosaur.shortDescription!.trim().isNotEmpty
        ? dinosaur.shortDescription!.trim()
        : '—';

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: ColoredBox(
        color: DinoCardTheme.cardBackground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DinosaurCardHeader(dinosaur: dinosaur),
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: DinoCardTheme.bodyStyle(fontSize: 11),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 88,
                child: GeologicTimeline(
                  birth: dinosaur.birth,
                  death: dinosaur.death,
                  axis: GeologicTimelineAxis.horizontal,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CladogramStrip(nodes: nodes),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
