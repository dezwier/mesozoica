import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/main_param_resolve.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/site_exploration_controller.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_section_panel.dart';
import 'site_dimension_display.dart';

/// Site card panel: four horizontal odd_* axes + vertical depth.
class SiteCardDimensions extends StatelessWidget {
  const SiteCardDimensions({super.key, required this.site});

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final emptyDims = site.needsIdentification;
    var showExactMarker = false;
    try {
      showExactMarker = context.watch<AuthController>().showAdminUi;
    } on ProviderNotFoundException {
      // Widget tests / previews without AuthController.
    }
    final skillLevel = _fieldSurveyLevel(context);
    final baseAccuracies = resolveSiteStewardshipAccuracies(
      skillLevel: skillLevel,
    );
    final baseAccuracy = baseAccuracies['documentation_accuracy'] ?? 0.0;
    final exploredM = emptyDims ? 0.0 : _resolvedExploredMeters(context, site);
    // Stack: shared skill baseline → per-dimension noise → exploration.
    final accuracies = <SiteDimensionKey, double>{
      for (final dim in SiteDimensionKey.values)
        dim: emptyDims
            ? 0.0
            : applyExplorationAccuracyBoost(
                applyDimensionAccuracyNoise(
                  baseAccuracy: baseAccuracy,
                  siteId: site.siteId,
                  dimension: dim,
                ),
                exploredM,
              ),
    };

    final horizontal =
        <(SiteDimensionKey, String, double?, SiteDimensionBand?)>[
          (
            SiteDimensionKey.dino,
            'Genera presence',
            emptyDims ? null : site.oddDinoCount,
            emptyDims ? null : site.oddDinoBand,
          ),
          (
            SiteDimensionKey.fossil,
            'Fossil presence',
            emptyDims ? null : site.oddFossilCount,
            emptyDims ? null : site.oddFossilBand,
          ),
          (
            SiteDimensionKey.completeness,
            'Completeness',
            emptyDims ? null : site.oddCompleteness,
            emptyDims ? null : site.oddCompletenessBand,
          ),
          (
            SiteDimensionKey.quality,
            'Preservation',
            emptyDims ? null : site.oddQuality,
            emptyDims ? null : site.oddQualityBand,
          ),
        ];

    final horizontalDisplays = <(String, SiteDimensionDisplay?, double)>[
      for (final entry in horizontal)
        (
          entry.$2,
          emptyDims
              ? null
              : _displayFor(
                  site: site,
                  key: entry.$1,
                  trueValue: entry.$3,
                  band: entry.$4,
                  accuracy: accuracies[entry.$1] ?? 0,
                  showExactMarker: showExactMarker,
                ),
          emptyDims ? 0.0 : (accuracies[entry.$1] ?? 0),
        ),
    ];
    final documentationDepth = emptyDims
        ? 0.0
        : (accuracies[SiteDimensionKey.depth] ?? 0);
    final depthDisplay = emptyDims
        ? null
        : _displayFor(
            site: site,
            key: SiteDimensionKey.depth,
            trueValue: site.oddDepth,
            band: site.oddDepthBand,
            accuracy: documentationDepth,
            showExactMarker: showExactMarker,
          );

    final dimensionAccuracies = <double>[
      for (final entry in horizontalDisplays)
        entry.$2?.effectiveAccuracy ?? entry.$3,
      depthDisplay?.effectiveAccuracy ?? documentationDepth,
    ];
    final avgDocumentedPct = emptyDims
        ? 0
        : ((dimensionAccuracies.reduce((a, b) => a + b) /
                          dimensionAccuracies.length)
                      .clamp(0.0, 1.0) *
                  100)
              .round();

    return CardSectionPanel(
      labelWidget: Text(
        emptyDims
            ? 'Identify site to begin documentation'
            : 'Documented $avgDocumentedPct% · Explored ${exploredM.floor()} m',
        textAlign: TextAlign.center,
        style: cardTheme
            .sectionLabelStyle(fontSize: 13)
            .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.15),
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 6, 10),
      labelGap: 8,
      child: SizedBox(
        height: 112,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < horizontalDisplays.length; i++) ...[
                    if (i > 0) const SizedBox(height: 5),
                    Expanded(
                      child: _HorizontalDimensionRow(
                        label: horizontalDisplays[i].$1,
                        accuracy: horizontalDisplays[i].$3,
                        display: horizontalDisplays[i].$2,
                        cardTheme: cardTheme,
                        showExactMarker: showExactMarker && !emptyDims,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              child: _VerticalDepthAxis(
                display: depthDisplay,
                accuracy: documentationDepth,
                cardTheme: cardTheme,
                showExactMarker: showExactMarker && !emptyDims,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _resolvedExploredMeters(
    BuildContext context,
    SiteSummary site,
  ) {
    final server = site.exploredDistanceM ?? 0.0;
    try {
      return context.watch<SiteExplorationController>().exploredMetersFor(
        site.siteId,
        fallback: server,
      );
    } on ProviderNotFoundException {
      return server;
    }
  }

  static int _fieldSurveyLevel(BuildContext context) {
    try {
      final profile = context.watch<AuthController>().currentUser;
      if (profile != null) {
        for (final skill in profile.skills) {
          if (skill.id == 'field_survey') return skill.level.clamp(1, 99);
        }
      }
    } on ProviderNotFoundException {
      // Widget tests / previews without AuthController.
    }
    return 1;
  }

  static String accuracyPercentLabel(double accuracy) {
    final pct = (accuracy.clamp(0.0, 1.0) * 100).round();
    return '$pct%';
  }

  static SiteDimensionDisplay? _displayFor({
    required SiteSummary site,
    required SiteDimensionKey key,
    required double? trueValue,
    required SiteDimensionBand? band,
    required double accuracy,
    required bool showExactMarker,
  }) {
    // Exact marker only when admin UI is on and the server sent exact odds.
    final exactValue = showExactMarker ? trueValue : null;

    if (trueValue != null) {
      final resolved = resolveSiteDimensionDisplay(
        dimension: key,
        trueValue: trueValue,
        accuracy: accuracy,
        siteId: site.siteId,
      );
      if (exactValue == null) {
        return SiteDimensionDisplay(
          rangeStart: resolved.rangeStart,
          rangeEnd: resolved.rangeEnd,
          blurSigma: resolved.blurSigma,
          effectiveAccuracy: resolved.effectiveAccuracy,
        );
      }
      return resolved;
    }

    if (band != null) {
      return _scaleBandToAccuracy(band, accuracy, exactValue: exactValue);
    }

    return null;
  }

  /// Shrink an existing server band toward its midpoint as accuracy rises.
  static SiteDimensionDisplay _scaleBandToAccuracy(
    SiteDimensionBand band,
    double accuracy, {
    double? exactValue,
  }) {
    final newAcc = accuracy.clamp(0.0, 1.0);
    final oldAcc = band.effectiveAccuracy.clamp(0.0, 1.0);
    if ((newAcc - oldAcc).abs() < 1e-9) {
      return SiteDimensionDisplay(
        trueValue: exactValue,
        rangeStart: band.rangeStart,
        rangeEnd: band.rangeEnd,
        blurSigma: band.blurSigma,
        effectiveAccuracy: band.effectiveAccuracy,
      );
    }
    final oldUncertainty = (1.0 - oldAcc).clamp(0.0, 1.0);
    final newUncertainty = 1.0 - newAcc;
    final scale = oldUncertainty > 1e-9
        ? (newUncertainty / oldUncertainty)
        : 0.0;
    final mid = (band.rangeStart + band.rangeEnd) / 2.0;
    final half = ((band.rangeEnd - band.rangeStart) / 2.0) * scale;
    return SiteDimensionDisplay(
      trueValue: exactValue,
      rangeStart: (mid - half).clamp(0.0, 1.0),
      rangeEnd: (mid + half).clamp(0.0, 1.0),
      blurSigma: band.blurSigma * scale,
      effectiveAccuracy: newAcc,
    );
  }
}

class _HorizontalDimensionRow extends StatelessWidget {
  const _HorizontalDimensionRow({
    required this.label,
    required this.accuracy,
    required this.display,
    required this.cardTheme,
    required this.showExactMarker,
  });

  final String label;
  final double accuracy;
  final SiteDimensionDisplay? display;
  final DinoCardTheme cardTheme;
  final bool showExactMarker;

  @override
  Widget build(BuildContext context) {
    final labelStyle = cardTheme.statLabelStyle(fontSize: 8.5);
    final accuracyStyle = labelStyle.copyWith(
      color: cardTheme.cardAccent,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.25,
    );
    // Prefer live effective accuracy from the display when present.
    final shownAccuracy = display?.effectiveAccuracy ?? accuracy;
    return Row(
      children: [
        SizedBox(
          width: 128,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${label.toUpperCase()} ',
                  style: labelStyle.copyWith(letterSpacing: 0.3),
                ),
                TextSpan(
                  text: SiteCardDimensions.accuracyPercentLabel(shownAccuracy),
                  style: accuracyStyle,
                ),
              ],
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: display == null
              ? _AxisTrackPlaceholder(cardTheme: cardTheme)
              : CustomPaint(
                  painter: _HorizontalAxisPainter(
                    rangeStart: display!.rangeStart,
                    rangeEnd: display!.rangeEnd,
                    trueValue: display!.trueValue,
                    accuracy: display!.effectiveAccuracy,
                    showExactMarker: showExactMarker,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.28),
                    tickColor: cardTheme.cardTextMuted.withValues(alpha: 0.45),
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
    required this.accuracy,
    required this.cardTheme,
    required this.showExactMarker,
  });

  final SiteDimensionDisplay? display;
  final double accuracy;
  final DinoCardTheme cardTheme;
  final bool showExactMarker;

  @override
  Widget build(BuildContext context) {
    final labelStyle = cardTheme.statLabelStyle(fontSize: 8.5);
    final accuracyStyle = labelStyle.copyWith(
      color: cardTheme.cardAccent,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );
    final shownAccuracy = display?.effectiveAccuracy ?? accuracy;
    return Column(
      children: [
        Text(
          'DEPTH',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle.copyWith(letterSpacing: 0.3),
        ),
        Text(
          SiteCardDimensions.accuracyPercentLabel(shownAccuracy),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: accuracyStyle,
        ),
        const SizedBox(height: 2),
        Expanded(
          child: display == null
              ? _AxisTrackPlaceholder(cardTheme: cardTheme, vertical: true)
              : CustomPaint(
                  painter: _VerticalAxisPainter(
                    rangeStart: display!.rangeStart,
                    rangeEnd: display!.rangeEnd,
                    trueValue: display!.trueValue,
                    accuracy: display!.effectiveAccuracy,
                    showExactMarker: showExactMarker,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.28),
                    tickColor: cardTheme.cardTextMuted.withValues(alpha: 0.45),
                    bandColor: cardTheme.cardAccent,
                  ),
                ),
        ),
      ],
    );
  }
}

class _AxisTrackPlaceholder extends StatelessWidget {
  const _AxisTrackPlaceholder({required this.cardTheme, this.vertical = false});

  final DinoCardTheme cardTheme;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: vertical
          ? _VerticalAxisPainter(
              rangeStart: null,
              rangeEnd: null,
              trueValue: null,
              accuracy: 0,
              showExactMarker: false,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.22),
              tickColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
              bandColor: Colors.transparent,
            )
          : _HorizontalAxisPainter(
              rangeStart: null,
              rangeEnd: null,
              trueValue: null,
              accuracy: 0,
              showExactMarker: false,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.22),
              tickColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
              bandColor: Colors.transparent,
            ),
    );
  }
}

class _HorizontalAxisPainter extends CustomPainter {
  _HorizontalAxisPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.trueValue,
    required this.accuracy,
    required this.showExactMarker,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double? trueValue;
  final double accuracy;
  final bool showExactMarker;
  final Color trackColor;
  final Color tickColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    _paintHorizontalTrack(canvas, size, cy);

    if (rangeStart == null || rangeEnd == null) return;

    final lo = rangeStart!.clamp(0.0, 1.0);
    final hi = rangeEnd!.clamp(0.0, 1.0);
    final x0 = lo * size.width;
    final x1 = hi * size.width;
    final center = Offset((x0 + x1) / 2, cy);

    if (accuracy >= 0.995) {
      _paintPreciseMarker(canvas, center, color: bandColor, vertical: false);
      return;
    }

    const bandH = 14.0;
    _paintRangeBand(
      canvas,
      Rect.fromLTRB(x0, cy - bandH / 2, math.max(x1, x0 + 2.5), cy + bandH / 2),
      color: bandColor,
    );

    if (showExactMarker && trueValue != null) {
      final exact = Offset(trueValue!.clamp(0.0, 1.0) * size.width, cy);
      _paintPreciseMarker(canvas, exact, color: bandColor, vertical: false);
    }
  }

  void _paintHorizontalTrack(Canvas canvas, Size size, double cy) {
    const trackH = 5.0;
    // Soft trough behind the rail.
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        cy - trackH,
        size.width,
        cy + trackH,
        const Radius.circular(2),
      ),
      Paint()..color = trackColor.withValues(alpha: trackColor.a * 0.45),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        cy - trackH / 2,
        size.width,
        cy + trackH / 2,
        const Radius.circular(1.25),
      ),
      Paint()..color = trackColor,
    );
    // End + mid ticks for scale.
    for (final t in const [0.0, 0.5, 1.0]) {
      final x = t * size.width;
      final tickH = t == 0.5 ? 5.0 : 3.5;
      canvas.drawLine(
        Offset(x, cy - tickH),
        Offset(x, cy + tickH),
        Paint()
          ..color = tickColor
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HorizontalAxisPainter oldDelegate) {
    return oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.trueValue != trueValue ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.showExactMarker != showExactMarker ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.bandColor != bandColor;
  }
}

class _VerticalAxisPainter extends CustomPainter {
  _VerticalAxisPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.trueValue,
    required this.accuracy,
    required this.showExactMarker,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double? trueValue;
  final double accuracy;
  final bool showExactMarker;
  final Color trackColor;
  final Color tickColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    _paintVerticalTrack(canvas, size, cx);

    if (rangeStart == null || rangeEnd == null) return;

    // Depth: 0 at top (surface / in situ), 1 at bottom.
    final lo = rangeStart!.clamp(0.0, 1.0);
    final hi = rangeEnd!.clamp(0.0, 1.0);
    final y0 = lo * size.height;
    final y1 = hi * size.height;
    final center = Offset(cx, (y0 + y1) / 2);

    if (accuracy >= 0.995) {
      _paintPreciseMarker(canvas, center, color: bandColor, vertical: true);
      return;
    }

    const bandW = 14.0;
    _paintRangeBand(
      canvas,
      Rect.fromLTRB(cx - bandW / 2, y0, cx + bandW / 2, math.max(y1, y0 + 2.5)),
      color: bandColor,
    );

    if (showExactMarker && trueValue != null) {
      final exact = Offset(cx, trueValue!.clamp(0.0, 1.0) * size.height);
      _paintPreciseMarker(canvas, exact, color: bandColor, vertical: true);
    }
  }

  void _paintVerticalTrack(Canvas canvas, Size size, double cx) {
    const trackW = 5.0;
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - trackW,
        0,
        cx + trackW,
        size.height,
        const Radius.circular(2),
      ),
      Paint()..color = trackColor.withValues(alpha: trackColor.a * 0.45),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        cx - trackW / 2,
        0,
        cx + trackW / 2,
        size.height,
        const Radius.circular(1.25),
      ),
      Paint()..color = trackColor,
    );
    for (final t in const [0.0, 0.5, 1.0]) {
      final y = t * size.height;
      final tickW = t == 0.5 ? 5.0 : 3.5;
      canvas.drawLine(
        Offset(cx - tickW, y),
        Offset(cx + tickW, y),
        Paint()
          ..color = tickColor
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalAxisPainter oldDelegate) {
    return oldDelegate.rangeStart != rangeStart ||
        oldDelegate.rangeEnd != rangeEnd ||
        oldDelegate.trueValue != trueValue ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.showExactMarker != showExactMarker ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.bandColor != bandColor;
  }
}

void _paintPreciseMarker(
  Canvas canvas,
  Offset center, {
  required Color color,
  required bool vertical,
}) {
  // Soft halo so the pip reads against the track.
  canvas.drawCircle(
    center,
    6.5,
    Paint()
      ..color = color.withValues(alpha: 0.22)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.2),
  );

  // Diamond pip — crisp and readable at accuracy 1.
  final path = Path()
    ..moveTo(center.dx, center.dy - 4.6)
    ..lineTo(center.dx + 3.6, center.dy)
    ..lineTo(center.dx, center.dy + 4.6)
    ..lineTo(center.dx - 3.6, center.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1,
  );
  canvas.drawCircle(
    center,
    1.35,
    Paint()..color = Colors.white.withValues(alpha: 0.95),
  );

  // Tiny axis tick through the marker for extra precision cue.
  final tickPaint = Paint()
    ..color = color.withValues(alpha: 0.85)
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  if (vertical) {
    canvas.drawLine(
      Offset(center.dx, center.dy - 7),
      Offset(center.dx, center.dy + 7),
      tickPaint,
    );
  } else {
    canvas.drawLine(
      Offset(center.dx - 7, center.dy),
      Offset(center.dx + 7, center.dy),
      tickPaint,
    );
  }
}

/// Timeline-style range band: solid fill + border, no blur haze.
void _paintRangeBand(Canvas canvas, Rect rect, {required Color color}) {
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
  canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.2));
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
}
