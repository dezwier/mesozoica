import 'package:flutter/material.dart';

import 'museum_card_frame.dart';

/// Top-left chip showing occurrence id and image version (e.g. `#67 · Original`).
class OccurrenceIdBadge extends StatelessWidget {
  const OccurrenceIdBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final text = label.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    return MuseumSectionTab(
      label: text,
      edge: MuseumSectionTabEdge.left,
      fontSize: 9,
      soft: true,
    );
  }
}
