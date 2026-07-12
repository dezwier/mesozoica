import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'site_card_back.dart';
import 'site_card_front.dart';
import 'turnable_y_axis_card.dart';

class SiteTurnableCard extends StatelessWidget {
  const SiteTurnableCard({
    super.key,
    required this.site,
    this.turnable = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.38,
  });

  final SiteSummary site;
  final bool turnable;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    return TurnableYAxisCard(
      resetIdentity: site.siteId,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: turnable,
      front: SiteCardFront(
        site: site,
        titleFontSize: titleFontSize,
        subtitleFontSize: subtitleFontSize,
        overlayHeightFactor: overlayHeightFactor,
      ),
      back: SiteCardBack(site: site),
    );
  }
}
