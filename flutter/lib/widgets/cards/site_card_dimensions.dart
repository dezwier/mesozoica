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
      (SiteDimensionKey.dino, 'Dinos', site.oddDinoCount),
      (SiteDimensionKey.fossil, 'Fossils', site.oddFossilCount),
      (SiteDimensionKey.completeness, 'Complete', site.oddCompleteness),
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
              width: 36,
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
          width: 52,
          child: Text(
            label.toUpperCase(),
            style: cardTheme.statLabelStyle(fontSize: 7),
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
                    value: display!.displayValue,
                    blurSigma: display!.blurSigma,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
                    fillColor: cardTheme.cardAccent.withValues(alpha: 0.55),
                    markerColor: cardTheme.cardAccent,
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
                    value: display!.displayValue,
                    blurSigma: display!.blurSigma,
                    trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.35),
                    fillColor: cardTheme.cardAccent.withValues(alpha: 0.55),
                    markerColor: cardTheme.cardAccent,
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
              value: null,
              blurSigma: 0,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.25),
              fillColor: Colors.transparent,
              markerColor: Colors.transparent,
            )
          : _HorizontalAxisPainter(
              value: null,
              blurSigma: 0,
              trackColor: cardTheme.cardTextMuted.withValues(alpha: 0.25),
              fillColor: Colors.transparent,
              markerColor: Colors.transparent,
            ),
    );
  }
}

class _HorizontalAxisPainter extends CustomPainter {
  _HorizontalAxisPainter({
    required this.value,
    required this.blurSigma,
    required this.trackColor,
    required this.fillColor,
    required this.markerColor,
  });

  final double? value;
  final double blurSigma;
  final Color trackColor;
  final Color fillColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 3.0;
    final trackR = RRect.fromLTRBR(
      0,
      cy - trackH / 2,
      size.width,
      cy + trackH / 2,
      const Radius.circular(1.5),
    );
    canvas.drawRRect(trackR, Paint()..color = trackColor);

    if (value == null) return;

    final x = value!.clamp(0.0, 1.0) * size.width;
    if (x > 0) {
      final fillR = RRect.fromLTRBR(
        0,
        cy - trackH / 2,
        x,
        cy + trackH / 2,
        const Radius.circular(1.5),
      );
      canvas.drawRRect(fillR, Paint()..color = fillColor);
    }

    _paintSoftMarker(
      canvas,
      Offset(x, cy),
      radius: 4.0,
      color: markerColor,
      blurSigma: blurSigma,
    );
  }

  @override
  bool shouldRepaint(covariant _HorizontalAxisPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.markerColor != markerColor;
  }
}

class _VerticalAxisPainter extends CustomPainter {
  _VerticalAxisPainter({
    required this.value,
    required this.blurSigma,
    required this.trackColor,
    required this.fillColor,
    required this.markerColor,
  });

  final double? value;
  final double blurSigma;
  final Color trackColor;
  final Color fillColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const trackW = 3.0;
    final trackR = RRect.fromLTRBR(
      cx - trackW / 2,
      0,
      cx + trackW / 2,
      size.height,
      const Radius.circular(1.5),
    );
    canvas.drawRRect(trackR, Paint()..color = trackColor);

    if (value == null) return;

    // Depth: 0 at top (surface), 1 at bottom.
    final y = value!.clamp(0.0, 1.0) * size.height;
    if (y > 0) {
      final fillR = RRect.fromLTRBR(
        cx - trackW / 2,
        0,
        cx + trackW / 2,
        y,
        const Radius.circular(1.5),
      );
      canvas.drawRRect(fillR, Paint()..color = fillColor);
    }

    _paintSoftMarker(
      canvas,
      Offset(cx, y),
      radius: 4.0,
      color: markerColor,
      blurSigma: blurSigma,
    );
  }

  @override
  bool shouldRepaint(covariant _VerticalAxisPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.markerColor != markerColor;
  }
}

void _paintSoftMarker(
  Canvas canvas,
  Offset center, {
  required double radius,
  required Color color,
  required double blurSigma,
}) {
  if (blurSigma > 0.05) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blurSigma);
    // Wider soft cloud so low accuracy visually covers more of the axis.
    canvas.drawCircle(center, radius + blurSigma * 1.4, paint);
  }
  canvas.drawCircle(
    center,
    radius,
    Paint()..color = color,
  );
  canvas.drawCircle(
    center,
    radius * 0.35,
    Paint()..color = Colors.white.withValues(alpha: 0.85),
  );
}
