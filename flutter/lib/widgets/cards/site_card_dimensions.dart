import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_section_panel.dart';
import 'site_dimension_display.dart';

/// Site card panel: four horizontal odd_* axes + vertical depth.
class SiteCardDimensions extends StatelessWidget {
  const SiteCardDimensions({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final accuracies = _accuraciesFor();

    final horizontal = <(SiteDimensionKey, String, double?)>[
      (SiteDimensionKey.dino, 'Dino count', site.oddDinoCount),
      (SiteDimensionKey.fossil, 'Fossils count', site.oddFossilCount),
      (SiteDimensionKey.completeness, 'Completeness', site.oddCompleteness),
      (SiteDimensionKey.quality, 'Quality', site.oddQuality),
    ];

    final horizontalDisplays = <(String, SiteDimensionDisplay?)>[
      for (final entry in horizontal)
        (
          entry.$2,
          _displayFor(
            site: site,
            key: entry.$1,
            trueValue: entry.$3,
            accuracy: accuracies[entry.$1]!,
          ),
        ),
    ];
    final depthDisplay = _displayFor(
      site: site,
      key: SiteDimensionKey.depth,
      trueValue: site.oddDepth,
      accuracy: accuracies[SiteDimensionKey.depth]!,
    );

    return CardSectionPanel(
      label: 'Site dimensions',
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SizedBox(
        height: 88,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < horizontalDisplays.length; i++) ...[
                    if (i > 0) const SizedBox(height: 4),
                    Expanded(
                      child: _HorizontalDimensionRow(
                        label: horizontalDisplays[i].$1,
                        display: horizontalDisplays[i].$2,
                        cardTheme: cardTheme,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: _VerticalDepthAxis(
                display: depthDisplay,
                cardTheme: cardTheme,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Map<SiteDimensionKey, double> _accuraciesFor() {
    if (!GameConfig.isLoaded) {
      return {
        for (final key in SiteDimensionKey.values) key: 0.0,
      };
    }
    final mp = GameConfig.instance.siteSurvey.mainParams;
    return {
      SiteDimensionKey.dino: mp.dinoAccuracy,
      SiteDimensionKey.fossil: mp.fossilAccuracy,
      SiteDimensionKey.completeness: mp.completenessAccuracy,
      SiteDimensionKey.quality: mp.qualityAccuracy,
      SiteDimensionKey.depth: mp.depthAccuracy,
    };
  }

  static SiteDimensionDisplay? _displayFor({
    required SiteSummary site,
    required SiteDimensionKey key,
    required double? trueValue,
    required double accuracy,
  }) {
    if (trueValue == null) return null;
    return resolveSiteDimensionDisplay(
      dimension: key,
      trueValue: trueValue,
      accuracy: accuracy,
      siteId: site.siteId,
    );
  }
}

class _HorizontalDimensionRow extends StatelessWidget {
  const _HorizontalDimensionRow({
    required this.label,
    required this.display,
    required this.cardTheme,
  });

  final String label;
  final SiteDimensionDisplay? display;
  final DinoCardTheme cardTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label.toUpperCase(),
            style: cardTheme.statLabelStyle(fontSize: 6.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: display == null
              ? _AxisTrackPlaceholder(cardTheme: cardTheme)
              : CustomPaint(
                  painter: _HorizontalAxisPainter(
                    rangeStart: display!.rangeStart,
                    rangeEnd: display!.rangeEnd,
                    blurSigma: display!.blurSigma,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
                    bandColor: cardTheme.cardAccent,
                  ),
                ),
        ),
      ],
    );
  }
}

class _VerticalDepthAxis extends StatelessWidget {
  const _VerticalDepthAxis({
    required this.display,
    required this.cardTheme,
  });

  final SiteDimensionDisplay? display;
  final DinoCardTheme cardTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'DEPTH',
          style: cardTheme.statLabelStyle(fontSize: 6.5),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Expanded(
          child: display == null
              ? _AxisTrackPlaceholder(cardTheme: cardTheme, vertical: true)
              : CustomPaint(
                  painter: _VerticalAxisPainter(
                    rangeStart: display!.rangeStart,
                    rangeEnd: display!.rangeEnd,
                    blurSigma: display!.blurSigma,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
                    bandColor: cardTheme.cardAccent,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AxisTrackPlaceholder extends StatelessWidget {
  const _AxisTrackPlaceholder({
    required this.cardTheme,
    this.vertical = false,
  });

  final DinoCardTheme cardTheme;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: vertical
          ? _VerticalAxisPainter(
              rangeStart: null,
              rangeEnd: null,
              blurSigma: 0,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.25),
              bandColor: Colors.transparent,
            )
          : _HorizontalAxisPainter(
              rangeStart: null,
              rangeEnd: null,
              blurSigma: 0,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.25),
              bandColor: Colors.transparent,
            ),
    );
  }
}

class _HorizontalAxisPainter extends CustomPainter {
  _HorizontalAxisPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.trackColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double blurSigma;
  final Color trackColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 3.0;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        cy - trackH / 2,
        size.width,
        cy + trackH / 2,
        const Radius.circular(1.5),
      ),
      Paint()..color = trackColor,
    );

    if (rangeStart == null || rangeEnd == null) return;

    final lo = rangeStart!.clamp(0.0, 1.0);
    final hi = rangeEnd!.clamp(0.0, 1.0);
    final x0 = lo * size.width;
    final x1 = hi * size.width;
    final bandH = (5.0 + blurSigma * 0.55).clamp(5.0, 12.0);

    _paintSoftBand(
      canvas,
      Rect.fromLTRB(x0, cy - bandH / 2, math.max(x1, x0 + 2.0), cy + bandH / 2),
      color: bandColor,
      blurSigma: blurSigma,
      radius: bandH / 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HorizontalAxisPainter oldDelegate) {
    return oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.bandColor != bandColor;
  }
}

class _VerticalAxisPainter extends CustomPainter {
  _VerticalAxisPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.trackColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double blurSigma;
  final Color trackColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const trackW = 3.0;
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - trackW / 2,
        0,
        cx + trackW / 2,
        size.height,
        const Radius.circular(1.5),
      ),
      Paint()..color = trackColor,
    );

    if (rangeStart == null || rangeEnd == null) return;

    // Depth: 0 at top (surface / in situ), 1 at bottom.
    final lo = rangeStart!.clamp(0.0, 1.0);
    final hi = rangeEnd!.clamp(0.0, 1.0);
    final y0 = lo * size.height;
    final y1 = hi * size.height;
    final bandW = (5.0 + blurSigma * 0.55).clamp(5.0, 14.0);

    _paintSoftBand(
      canvas,
      Rect.fromLTRB(cx - bandW / 2, y0, cx + bandW / 2, math.max(y1, y0 + 2.0)),
      color: bandColor,
      blurSigma: blurSigma,
      radius: bandW / 2,
    );
  }

  @override
  bool shouldRepaint(covariant _VerticalAxisPainter oldDelegate) {
    return oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.bandColor != bandColor;
  }
}

void _paintSoftBand(
  Canvas canvas,
  Rect rect, {
  required Color color,
  required double blurSigma,
  required double radius,
}) {
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

  if (blurSigma > 0.05) {
    // Soft outer haze — wideness + blur hide the true value.
    canvas.drawRRect(
      rrect.inflate(blurSigma * 0.65),
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blurSigma),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter =
            ui.MaskFilter.blur(ui.BlurStyle.normal, blurSigma * 0.55),
    );
  }

  // Core band — sharp when accurate, still soft-edged when not.
  canvas.drawRRect(
    rrect,
    Paint()..color = color.withValues(alpha: blurSigma > 0.05 ? 0.72 : 0.95),
  );

  // Precise tip highlight when the band collapses.
  if (blurSigma <= 0.05 && rect.shortestSide <= 6) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    canvas.drawCircle(
      Offset(cx, cy),
      3.2,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      1.1,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }
}
