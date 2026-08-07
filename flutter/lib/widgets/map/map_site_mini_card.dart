import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/auth_controller.dart';
import '../../features/discovery/discovery.dart';
import '../../theme/map_chrome_decorations.dart';
import '../../theme/map_chrome_theme.dart';
import '../cards/site_card_image.dart';
import '../cards/site_card_header.dart';

/// Mockup site pin: photo circle, dark pointer behind image, cream label.
class MapSiteMiniCard extends StatelessWidget {
  const MapSiteMiniCard({
    super.key,
    required this.site,
    this.selected = false,
    this.disguised = false,
    this.width = MapConfig.rotateMiniCardWidth,
    this.distanceM,
  });

  final SiteSummary site;
  final bool selected;

  /// Active disguise cover on this site (subtle light-gold title).
  final bool disguised;
  final double width;

  /// When set, shown under the site title (e.g. `153 m`).
  final double? distanceM;

  /// Pale gold for disguised site titles (light, not brown).
  static const Color disguisedLabelGold = Color(0xFFD4B86A);

  static const double _borderWidth = 2.5;
  static const double _triangleH = 12;
  static const double _triangleW = 14;
  static const double _dot = 5;
  static const double _labelOverlap = 14;

  /// Cream label width relative to photo — wide enough for `999 m · Documented`.
  static const double _labelWidthFactor = 2.45;

  /// Total pin height from top of photo to bottom of ground dot.
  static double heightForWidth(double width) {
    // Triangle starts behind the image (~40% overlap).
    final triangleVisible = _triangleH * 0.6;
    return width + triangleVisible + 2 + _dot;
  }

  /// Horizontal span including the cream label to the right of the photo.
  static double layoutWidthFor(double photoWidth) =>
      photoWidth - _labelOverlap + photoWidth * _labelWidthFactor;

  /// Offset from layout left to the ground-dot center (photo center).
  static double anchorXFor(double photoWidth) => photoWidth / 2;

  /// Offset from layout top to the ground-dot center.
  static double anchorYFor(double photoWidth) => heightForWidth(photoWidth);

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  /// Distance and/or live site status for the cream label subtitle.
  static String? subtitleFor({double? distanceM, String? status}) {
    final trimmed = status?.trim();
    final statusLabel =
        (trimmed == null ||
            trimmed.isEmpty ||
            trimmed.toLowerCase() == 'hidden')
        ? null
        : siteFilterOptionLabel(trimmed);
    if (distanceM != null && statusLabel != null) {
      return '${formatDistance(distanceM)} · $statusLabel';
    }
    if (distanceM != null) return formatDistance(distanceM);
    return statusLabel;
  }

  @override
  Widget build(BuildContext context) {
    final photo = width;
    final documentation = _documentAccuracy(context);
    final triangleTop = photo - _triangleH * 0.4;
    final labelMaxWidth = photo * _labelWidthFactor;
    final titleColor = disguised
        ? MapSiteMiniCard.disguisedLabelGold
        : MapChromeTheme.brownText;
    final subtitle = subtitleFor(distanceM: distanceM, status: site.status);
    final stars = site.documentationStars;

    return SizedBox(
      width: layoutWidthFor(photo),
      height: heightForWidth(photo),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Dark pointer — painted first so it sits behind the photo.
          Positioned(
            left: (photo - _triangleW) / 2,
            top: triangleTop,
            width: _triangleW,
            height: _triangleH,
            child: const CustomPaint(
              painter: _PinTrianglePainter(color: Color(0xFF2A2420)),
            ),
          ),
          // Ground dot
          Positioned(
            left: (photo - _dot) / 2,
            top: triangleTop + _triangleH + 1,
            width: _dot,
            height: _dot,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? MapChromeTheme.goldBright
                    : disguised
                    ? MapSiteMiniCard.disguisedLabelGold
                    : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          // Cream label — starts behind the right edge of the photo, vertically
          // centered with the image.
          Positioned(
            left: photo - _labelOverlap,
            top: 0,
            height: photo,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: DecoratedBox(
                  decoration: MapChromeDecorations.parchmentPanel(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: CustomPaint(
                            painter: ParchmentGrainPainter(alpha: 0.015),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            _labelOverlap + 4,
                            5,
                            10,
                            5,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                site.displayTitle,
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 1),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MapChromeTheme.labelMuted,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Photo circle on top so border + image cover triangle/label overlap.
          Positioned(
            left: 0,
            top: 0,
            width: photo,
            height: photo,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SiteDocumentationMarkerRing(
                progress: documentation,
                strokeWidth: _borderWidth,
                progressColor: MapChromeTheme.gold,
                child: Padding(
                  padding: const EdgeInsets.all(_borderWidth),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SiteCardImage(imageUrl: site.mainImageUrl),
                        if (stars != null)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.center,
                              child: SiteRatingStars(
                                stars: stars,
                                starSize: photo * 0.16,
                                color: const Color(0xFFE6C35C),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _documentAccuracy(BuildContext context) {
    var progress = site.documentationProgress ?? 0.0;
    var skillLevel = 1;
    try {
      progress = context
          .watch<SiteExplorationController>()
          .documentationProgressFor(site.siteId, fallback: progress);
    } on ProviderNotFoundException {
      // Static previews use the server snapshot.
    }
    try {
      final profile = context.watch<AuthController>().currentUser;
      for (final skill in profile?.skills ?? const []) {
        if (skill.id == 'field_survey') {
          skillLevel = skill.level.clamp(1, 99);
          break;
        }
      }
    } on ProviderNotFoundException {
      // Static previews use level one.
    }
    if (site.documented == true) return 1.0;
    return siteDocumentationAverageAccuracy(
      siteId: site.siteId,
      skillLevel: skillLevel,
      documentationProgress: progress,
      oddDepth: site.oddDepth,
      serverAccuracies: {
        SiteDimensionKey.dino: site.oddDinoBand?.effectiveAccuracy ?? 0.0,
        SiteDimensionKey.fossil: site.oddFossilBand?.effectiveAccuracy ?? 0.0,
        SiteDimensionKey.completeness:
            site.oddCompletenessBand?.effectiveAccuracy ?? 0.0,
        SiteDimensionKey.quality: site.oddQualityBand?.effectiveAccuracy ?? 0.0,
        SiteDimensionKey.depth: site.oddDepthBand?.effectiveAccuracy ?? 0.0,
      },
    );
  }
}

class _PinTrianglePainter extends CustomPainter {
  const _PinTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
