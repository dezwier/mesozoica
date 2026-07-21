import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'card_adaptive_title_text.dart';

/// Two-line map mini-card label: period on line 1, rock type on line 2.
class SitePeriodRockTypeLines extends StatelessWidget {
  const SitePeriodRockTypeLines({
    super.key,
    required this.site,
    required this.fontSize,
    this.overlayOnImage = true,
    this.mapMarker = false,
  });

  final SiteSummary site;
  final double fontSize;
  final bool overlayOnImage;
  final bool mapMarker;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final style = mapMarker
        ? cardTheme.mapMarkerLabelStyle(fontSize: fontSize)
        : overlayOnImage
            ? cardTheme.frontOverlayTitleStyle(fontSize: fontSize)
            : cardTheme.frontTitleStyle(fontSize: fontSize);

    final periodRaw = site.effectivePeriod;
    final periodLine = (periodRaw != null && periodRaw.isNotEmpty)
        ? toTitleCase(periodRaw)
        : site.displaySiteNumber;

    final rockRaw = (site.rockType ?? site.siteTypeRockType)?.trim();
    final rockLine =
        (rockRaw != null && rockRaw.isNotEmpty) ? toTitleCase(rockRaw) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardAdaptiveTitleText(
          text: periodLine,
          style: style,
          textAlign: TextAlign.center,
        ),
        if (rockLine != null) ...[
          SizedBox(height: fontSize * 0.12),
          CardAdaptiveTitleText(
            text: rockLine,
            style: style,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
