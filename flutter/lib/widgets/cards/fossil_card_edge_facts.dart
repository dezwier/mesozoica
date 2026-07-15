import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../utils/display_text.dart';
import 'card_fact_badge.dart';

/// Attribute panel for the fossil card back.
class FossilCardEdgeFacts extends StatelessWidget {
  const FossilCardEdgeFacts({
    super.key,
    required this.fossil,
  });

  final FossilSummary fossil;

  @override
  Widget build(BuildContext context) {
    return CardFactPanel(
      columns: 2,
      layout: CardFactPanelLayout.columnGrid,
      centerColumns: true,
      facts: [
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/diet.svg',
          label: 'Category',
          value: displayFactValue(
            fossil.displayCategory == '—' ? null : fossil.displayCategory,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/mass.svg',
          label: 'Sub category',
          value: displayFactValue(
            fossil.displaySubcategory == '—' ? null : fossil.displaySubcategory,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Preservation quality',
          value: displayFactValue(
            fossil.displayPreservationQuality == '—'
                ? null
                : fossil.displayPreservationQuality,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/length.svg',
          label: 'Completeness',
          value: displayFactValue(
            fossil.displayCompleteness == '—' ? null : fossil.displayCompleteness,
          ),
        ),
      ],
    );
  }
}
