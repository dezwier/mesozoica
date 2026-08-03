import 'package:flutter/material.dart';

import 'card_section_panel.dart';
import 'geologic_timeline.dart';

/// Shared card-back panel for the horizontal geologic timeline.
class CardGeologicTimelinePanel extends StatelessWidget {
  const CardGeologicTimelinePanel({
    super.key,
    this.minAgeMa,
    this.maxAgeMa,
    this.birth,
    this.death,
    this.scale = 1.15,
    this.height = 64,
  });

  /// PBDB-style age bounds (younger / older). Prefer these for fossils/sites.
  final double? minAgeMa;
  final double? maxAgeMa;

  /// Absolute Ma extents (dinosaurs). Used when [minAgeMa]/[maxAgeMa] are null.
  final double? birth;
  final double? death;

  final double scale;
  final double height;

  @override
  Widget build(BuildContext context) {
    final timeline = minAgeMa != null || maxAgeMa != null
        ? GeologicTimeline.fromAgeRange(
            minAgeMa: minAgeMa,
            maxAgeMa: maxAgeMa,
            axis: GeologicTimelineAxis.horizontal,
            scale: scale,
          )
        : GeologicTimeline(
            birth: birth,
            death: death,
            axis: GeologicTimelineAxis.horizontal,
            scale: scale,
          );

    return CardSectionPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SizedBox(
        height: height,
        child: timeline,
      ),
    );
  }
}
