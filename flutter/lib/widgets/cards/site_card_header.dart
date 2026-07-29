import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';

class SiteCardHeader extends StatelessWidget {
  const SiteCardHeader({
    super.key,
    required this.site,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.overlayOnImage = false,
    this.showSubtitle = true,
    this.subtitleOverride,
    this.titleMaxLines = 1,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool overlayOnImage;
  final bool showSubtitle;
  /// When set, shown as the subtitle instead of the collection line.
  final String? subtitleOverride;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = overlayOnImage
        ? cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize)
        : useFrontTitleStyle
            ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
            : cardTheme.titleStyle(fontSize: titleFontSize);
    final subtitleStyle = overlayOnImage
        ? cardTheme.frontOverlaySubtitleStyle(fontSize: subtitleFontSize)
        : cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
            color: cardTheme.cardTextMuted,
            fontWeight: FontWeight.w500,
          );
    final subtitle = subtitleOverride ??
        site.displaySubtitle(distanceMeters: _distanceMeters(context));

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (centered)
          SizedBox(
            width: double.infinity,
            child: CardAdaptiveTitleText(
              text: site.displayTitle,
              style: titleStyle,
              textAlign: TextAlign.center,
              maxLines: titleMaxLines,
            ),
          )
        else
          CardAdaptiveTitleText(
            text: site.displayTitle,
            style: titleStyle,
            textAlign: TextAlign.start,
            maxLines: titleMaxLines,
          ),
        if (showSubtitle && subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: subtitleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  double? _distanceMeters(BuildContext context) {
    final lat = site.latitude;
    final lon = site.longitude;
    if (lat == null || lon == null) return null;
    final user =
        Provider.of<LocationService?>(context, listen: true)?.currentLocation;
    if (user == null) return null;
    return Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      lat,
      lon,
    );
  }
}
