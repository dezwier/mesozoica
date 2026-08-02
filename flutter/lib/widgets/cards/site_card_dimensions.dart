import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/main_param_resolve.dart';
import '../../controllers/auth_controller.dart';
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
    final skillLevel = _siteSurveyLevel(context);
    final accuracies = resolveSiteSurveyAccuracies(skillLevel: skillLevel);

    final horizontal = <(SiteDimensionKey, String, String, double?)>[
      (SiteDimensionKey.dino, 'Dino count', 'dino_accuracy', site.oddDinoCount),
      (
        SiteDimensionKey.fossil,
        'Fossils count',
        'fossil_accuracy',
        site.oddFossilCount,
      ),
      (
        SiteDimensionKey.completeness,
        'Completeness',
        'completeness_accuracy',
        site.oddCompleteness,
      ),
      (
        SiteDimensionKey.quality,
        'Quality',
        'quality_accuracy',
        site.oddQuality,
      ),
    ];

    final horizontalDisplays = <(String, SiteDimensionDisplay?)>[
      for (final entry in horizontal)
        (
          entry.$2,
          _displayFor(
            site: site,
            key: entry.$1,
            trueValue: entry.$4,
            accuracy: accuracies[entry.$3] ?? 0,
          ),
        ),
    ];
    final depthDisplay = _displayFor(
      site: site,
      key: SiteDimensionKey.depth,
      trueValue: site.oddDepth,
      accuracy: accuracies['depth_accuracy'] ?? 0,
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

  static int _siteSurveyLevel(BuildContext context) {
    try {
      final profile = context.watch<AuthController>().currentUser;
      if (profile != null) {
        for (final skill in profile.skills) {
          if (skill.id == 'site_survey') return skill.level.clamp(1, 99);
        }
      }
    } on ProviderNotFoundException {
      // Widget tests / previews without AuthController.
    }
    return 1;
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
                    accuracy: display!.effectiveAccuracy,
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
                    accuracy: display!.effectiveAccuracy,
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
              blurSigma: 0,
              accuracy: 0,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.22),
              tickColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
              bandColor: Colors.transparent,
            )
          : _HorizontalAxisPainter(
              rangeStart: null,
              rangeEnd: null,
              blurSigma: 0,
              accuracy: 0,
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
    required this.blurSigma,
    required this.accuracy,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double blurSigma;
  final double accuracy;
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
    final bandH = (4.5 + blurSigma * 0.7).clamp(4.5, 14.0);
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
  }

  void _paintHorizontalTrack(Canvas canvas, Size size, double cy) {
    const trackH = 2.5;
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
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.accuracy != accuracy ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.bandColor != bandColor;
  }
}

class _VerticalAxisPainter extends CustomPainter {
  _VerticalAxisPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.blurSigma,
    required this.accuracy,
    required this.trackColor,
    required this.tickColor,
    required this.bandColor,
  });

  final double? rangeStart;
  final double? rangeEnd;
  final double blurSigma;
  final double accuracy;
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
    final bandW = (4.5 + blurSigma * 0.7).clamp(4.5, 16.0);
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
  }

  void _paintVerticalTrack(Canvas canvas, Size size, double cx) {
    const trackW = 2.5;
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
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.accuracy != accuracy ||
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
