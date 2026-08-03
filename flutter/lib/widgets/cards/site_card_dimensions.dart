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
  const SiteCardDimensions({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    var showExactMarker = false;
    try {
      showExactMarker = context.watch<AuthController>().showAdminUi;
    } on ProviderNotFoundException {
      // Widget tests / previews without AuthController.
    }
    final skillLevel = _siteStewardshipLevel(context);
    final baseAccuracies =
        resolveSiteStewardshipAccuracies(skillLevel: skillLevel);
    final exploredM = _resolvedExploredMeters(context, site);
    // Stack: skill baseline → per-dimension noise → exploration (tools later).
    const dimByAccuracyKey = <String, SiteDimensionKey>{
      'dino_accuracy': SiteDimensionKey.dino,
      'fossil_accuracy': SiteDimensionKey.fossil,
      'completeness_accuracy': SiteDimensionKey.completeness,
      'quality_accuracy': SiteDimensionKey.quality,
      'depth_accuracy': SiteDimensionKey.depth,
    };
    final accuracies = {
      for (final e in baseAccuracies.entries)
        e.key: applyExplorationAccuracyBoost(
          applyDimensionAccuracyNoise(
            baseAccuracy: e.value,
            siteId: site.siteId,
            dimension: dimByAccuracyKey[e.key]!,
          ),
          exploredM,
        ),
    };

    final horizontal =
        <(SiteDimensionKey, String, String, double?, SiteDimensionBand?)>[
      (
        SiteDimensionKey.dino,
        'Dino count',
        'dino_accuracy',
        site.oddDinoCount,
        site.oddDinoBand,
      ),
      (
        SiteDimensionKey.fossil,
        'Fossils count',
        'fossil_accuracy',
        site.oddFossilCount,
        site.oddFossilBand,
      ),
      (
        SiteDimensionKey.completeness,
        'Completeness',
        'completeness_accuracy',
        site.oddCompleteness,
        site.oddCompletenessBand,
      ),
      (
        SiteDimensionKey.quality,
        'Quality',
        'quality_accuracy',
        site.oddQuality,
        site.oddQualityBand,
      ),
    ];

    final horizontalDisplays =
        <(String, SiteDimensionDisplay?, double)>[
      for (final entry in horizontal)
        (
          entry.$2,
          _displayFor(
            site: site,
            key: entry.$1,
            trueValue: entry.$4,
            band: entry.$5,
            accuracy: accuracies[entry.$3] ?? 0,
            showExactMarker: showExactMarker,
          ),
          accuracies[entry.$3] ?? 0,
        ),
    ];
    final depthAccuracy = accuracies['depth_accuracy'] ?? 0;
    final depthDisplay = _displayFor(
      site: site,
      key: SiteDimensionKey.depth,
      trueValue: site.oddDepth,
      band: site.oddDepthBand,
      accuracy: depthAccuracy,
      showExactMarker: showExactMarker,
    );

    return CardSectionPanel(
      labelWidget: Text(
        'Site dimensions · mapped ${exploredM.floor()} m',
        textAlign: TextAlign.center,
        style: cardTheme.sectionLabelStyle(fontSize: 13).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      labelGap: 8,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.98,
          child: SizedBox(
            height: 104,
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
                            showExactMarker: showExactMarker,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: _VerticalDepthAxis(
                    display: depthDisplay,
                    accuracy: depthAccuracy,
                    cardTheme: cardTheme,
                    showExactMarker: showExactMarker,
                  ),
                ),
              ],
            ),
          ),
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
      return context
          .watch<SiteExplorationController>()
          .exploredMetersFor(site.siteId, fallback: server);
    } on ProviderNotFoundException {
      return server;
    }
  }

  static int _siteStewardshipLevel(BuildContext context) {
    try {
      final profile = context.watch<AuthController>().currentUser;
      if (profile != null) {
        for (final skill in profile.skills) {
          if (skill.id == 'site_stewardship') return skill.level.clamp(1, 99);
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
    final scale =
        oldUncertainty > 1e-9 ? (newUncertainty / oldUncertainty) : 0.0;
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
    final labelStyle = cardTheme.statLabelStyle(fontSize: 7);
    final accuracyStyle = labelStyle.copyWith(
      color: cardTheme.cardAccent,
      fontWeight: FontWeight.w700,
    );
    // Prefer live effective accuracy from the display when present.
    final shownAccuracy = display?.effectiveAccuracy ?? accuracy;
    return Row(
      children: [
        SizedBox(
          width: 98,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${label.toUpperCase()} ',
                  style: labelStyle,
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
        const SizedBox(width: 6),
        Expanded(
          child: display == null
              ? _AxisTrackPlaceholder(cardTheme: cardTheme)
              : CustomPaint(
                  painter: _HorizontalAxisPainter(
                    rangeStart: display!.rangeStart,
                    rangeEnd: display!.rangeEnd,
                    trueValue: display!.trueValue,
                    blurSigma: display!.blurSigma,
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
    final labelStyle = cardTheme.statLabelStyle(fontSize: 7);
    final accuracyStyle = labelStyle.copyWith(
      color: cardTheme.cardAccent,
      fontWeight: FontWeight.w700,
    );
    final shownAccuracy = display?.effectiveAccuracy ?? accuracy;
    return Column(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'DEPTH ', style: labelStyle),
              TextSpan(
                text: SiteCardDimensions.accuracyPercentLabel(shownAccuracy),
                style: accuracyStyle,
              ),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
                    blurSigma: display!.blurSigma,
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
              trueValue: null,
              blurSigma: 0,
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
              blurSigma: 0,
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
    required this.blurSigma,
    required this.accuracy,
    required this.showExactMarker,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double? trueValue;
  final double blurSigma;
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

    final uncertainty = (1.0 - accuracy).clamp(0.0, 1.0);
    final bandH = (6.0 + blurSigma * 0.75).clamp(6.0, 16.0);
    _paintUncertaintyBand(
      canvas,
      Rect.fromLTRB(
        x0,
        cy - bandH / 2,
        math.max(x1, x0 + 2.5),
        cy + bandH / 2,
      ),
      color: bandColor,
      blurSigma: blurSigma,
      uncertainty: uncertainty,
      vertical: false,
    );

    if (showExactMarker && trueValue != null) {
      final exact = Offset(trueValue!.clamp(0.0, 1.0) * size.width, cy);
      _paintPreciseMarker(canvas, exact, color: bandColor, vertical: false);
    }
  }

  void _paintHorizontalTrack(Canvas canvas, Size size, double cy) {
    const trackH = 3.5;
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
        oldDelegate.blurSigma != blurSigma ||
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
    required this.blurSigma,
    required this.accuracy,
    required this.showExactMarker,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double? trueValue;
  final double blurSigma;
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

    final uncertainty = (1.0 - accuracy).clamp(0.0, 1.0);
    final bandW = (6.0 + blurSigma * 0.75).clamp(6.0, 16.0);
    _paintUncertaintyBand(
      canvas,
      Rect.fromLTRB(
        cx - bandW / 2,
        y0,
        cx + bandW / 2,
        math.max(y1, y0 + 2.5),
      ),
      color: bandColor,
      blurSigma: blurSigma,
      uncertainty: uncertainty,
      vertical: true,
    );

    if (showExactMarker && trueValue != null) {
      final exact = Offset(cx, trueValue!.clamp(0.0, 1.0) * size.height);
      _paintPreciseMarker(canvas, exact, color: bandColor, vertical: true);
    }
  }

  void _paintVerticalTrack(Canvas canvas, Size size, double cx) {
    const trackW = 3.5;
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
        oldDelegate.blurSigma != blurSigma ||
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

void _paintUncertaintyBand(
  Canvas canvas,
  Rect rect, {
  required Color color,
  required double blurSigma,
  required double uncertainty,
  required bool vertical,
}) {
  final radius = math.min(rect.shortestSide / 2, 8.0);
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  final sigma = math.max(blurSigma, 1.0);

  // Wide atmospheric fog — dominates at accuracy 0.
  canvas.drawRRect(
    rrect.inflate(sigma * 1.15),
    Paint()
      ..color = color.withValues(alpha: 0.12 + uncertainty * 0.18)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma * 1.35),
  );
  canvas.drawRRect(
    rrect.inflate(sigma * 0.55),
    Paint()
      ..color = color.withValues(alpha: 0.18 + uncertainty * 0.22)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma * 0.9),
  );

  // Soft gradient core (not a hard bar) so the true value stays obscured.
  final shaderRect = vertical
      ? Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height)
      : Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
  final mid = color.withValues(alpha: 0.28 + (1.0 - uncertainty) * 0.35);
  final edge = color.withValues(alpha: 0.06 + (1.0 - uncertainty) * 0.12);
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        vertical ? shaderRect.topCenter : shaderRect.centerLeft,
        vertical ? shaderRect.bottomCenter : shaderRect.centerRight,
        [edge, mid, edge],
        const [0.0, 0.5, 1.0],
      )
      ..maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        sigma * (0.25 + uncertainty * 0.45),
      ),
  );

  // Faint inner streak only when somewhat accurate — still soft.
  if (uncertainty < 0.65) {
    final inset = uncertainty * 1.8;
    final core = rrect.deflate(inset);
    canvas.drawRRect(
      core,
      Paint()
        ..color = color.withValues(alpha: 0.35 * (1.0 - uncertainty))
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          1.2 + uncertainty * 2.5,
        ),
    );
  }
}
