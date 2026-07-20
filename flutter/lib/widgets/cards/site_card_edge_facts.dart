import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../utils/display_text.dart';
import 'card_fact_badge.dart';

/// Attribute panel for the site card back.
class SiteCardEdgeFacts extends StatelessWidget {
  const SiteCardEdgeFacts({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    return CardFactPanel(
      columns: 2,
      layout: CardFactPanelLayout.columnGrid,
      centerColumns: true,
      facts: [
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Coordinates',
          value: displayFactValue(
            site.displayCoordinates == '—' ? null : site.displayCoordinates,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/location.svg',
          label: 'Country',
          value: displayFactValue(
            site.displayCountry == '—' ? null : site.displayCountry,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/period.svg',
          label: 'Period',
          value: displayFactValue(
            site.displayPeriod == '—' ? null : site.displayPeriod,
          ),
        ),
        CardFactEntry(
          iconAsset: 'assets/images/cards/icons/mass.svg',
          label: 'Rock type',
          value: displayFactValue(
            site.rockType == null ? null : toTitleCase(site.rockType!),
          ),
        ),
      ],
    );
  }
}
