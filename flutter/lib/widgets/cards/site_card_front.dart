import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'occurrence_id_badge.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_period_rock_type_lines.dart';
import 'site_status_badge.dart';

class SiteCardFront extends StatelessWidget {
  const SiteCardFront({
    super.key,
    required this.site,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
    this.showSubtitle = true,
    this.showStatusBadge = true,
    this.titleHorizontalInset = 18,
    this.titleMaxLines = 1,
    this.usePeriodRockTypeLines = false,
    this.onStatusSelected,
    this.onSiteUpdated,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final bool showSubtitle;
  final bool showStatusBadge;
  final double titleHorizontalInset;
  final int titleMaxLines;
  final bool usePeriodRockTypeLines;
  final ValueChanged<String>? onStatusSelected;
  final ValueChanged<SiteSummary>? onSiteUpdated;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final status = site.status?.trim();
    final showIdBadge = site.isFieldOccurrence;
    final showStatus = showStatusBadge && status != null && status.isNotEmpty;
    final stars = site.documentationStars;
    final title = usePeriodRockTypeLines
        ? (site.titleIsRevealed
              ? SitePeriodRockTypeLines(site: site, fontSize: titleFontSize)
              : SiteCardHeader(
                  site: site,
                  titleFontSize: titleFontSize,
                  subtitleFontSize: subtitleFontSize,
                  centered: true,
                  overlayOnImage: true,
                  showSubtitle: false,
                ))
        : SiteCardHeader(
            site: site,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            centered: true,
            overlayOnImage: true,
            showSubtitle: showSubtitle,
            titleMaxLines: titleMaxLines,
          );

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SiteCardImage(imageUrl: site.mainImageUrl),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: overlayHeightFactor,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cardTheme.frontOverlayGradient(),
                  ),
                ),
              ),
            ),
          ),
          if (showIdBadge)
            Positioned(
              top: 14,
              left: 14,
              child: OccurrenceIdBadge(label: site.occurrenceIdBadgeLabel),
            ),
          if (showStatus)
            Positioned(
              top: 14,
              right: 14,
              child: SiteStatusBadge(
                status: status,
                onStatusSelected: onStatusSelected,
              ),
            ),
          Positioned(
            left: titleHorizontalInset,
            right: titleHorizontalInset,
            bottom: math.max(
              usePeriodRockTypeLines || titleMaxLines > 1 ? 5 : 16,
              titleFontSize *
                  (usePeriodRockTypeLines
                      ? 0.28
                      : titleMaxLines > 1
                      ? 0.35
                      : 0.45),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stars != null) ...[
                  Center(
                    child: SiteRatingStars(
                      stars: stars,
                      starSize: titleFontSize * 0.52,
                      color: const Color(0xFFE6C35C),
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                title,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
