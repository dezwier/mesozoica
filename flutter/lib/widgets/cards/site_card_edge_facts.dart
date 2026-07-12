import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'dino_fact_row.dart';

/// Subtle vertical attribute strip for the site card front right edge.
class SiteCardEdgeFacts extends StatelessWidget {
  const SiteCardEdgeFacts({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            cardTheme.cardBackground.withValues(alpha: 0.84),
            cardTheme.cardBackground.withValues(alpha: 0.74),
            cardTheme.cardBackground.withValues(alpha: 0.50),
            cardTheme.cardBackground.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.38, 0.72, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/location.svg',
              label: 'Coordinates',
              value: displayFactValue(
                site.displayCoordinates == '—' ? null : site.displayCoordinates,
              ),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/location.svg',
              label: 'Country',
              value: displayFactValue(
                site.displayCountry == '—' ? null : site.displayCountry,
              ),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/period.svg',
              label: 'Period',
              value: displayFactValue(
                site.displayPeriod == '—' ? null : site.displayPeriod,
              ),
              edge: true,
            ),
            DinoFactRow(
              iconAsset: 'assets/images/cards/icons/mass.svg',
              label: 'Rock type',
              value: displayFactValue(site.rockType),
              edge: true,
              rowPadding: 0,
            ),
          ],
        ),
      ),
    );
  }
}
