import 'package:flutter/material.dart';

import '../../utils/display_text.dart';
import 'museum_card_frame.dart';

/// Non-interactive status chip for inventory dinosaur occurrence cards.
class DinosaurStatusBadge extends StatelessWidget {
  const DinosaurStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = capitalizeLeadingLetter(status.trim());
    if (label.isEmpty) return const SizedBox.shrink();

    return MuseumSectionTab(
      label: label,
      edge: MuseumSectionTabEdge.right,
      fontSize: 9,
      soft: true,
    );
  }
}
