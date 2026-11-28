import 'package:flutter/material.dart';

import '../../config/geologic_timeline_constants.dart' as timeline_constants;
import '../../theme/dino_card_theme.dart';
import '../map/period_marker_color.dart';

enum GeologicTimelineAxis { vertical, horizontal }

/// Map pin hues from `period_colors.yaml` `site_markers`, with a static
/// fallback for widget tests that have not loaded [GameConfig].
Color _pinColor(String period) {
  try {
    return periodMarkerColor(period);
  } on StateError {
    switch (period.toLowerCase()) {
      case 'jurassic':
        return const Color(0xFF4F8F68);
      case 'triassic':
        return const Color(0xFFDD8500);
      case 'cretaceous':
      default:
        return const Color(0xFF8D6E63);
    }
  }
}

/// Deep-time scale from 252 Ma (Triassic start) to 66 Ma (Cretaceous end).
class GeologicTimeline extends StatelessWidget {
  const GeologicTimeline({
    super.key,
    this.birth,
    this.death,
    this.minMa = mesozoicOlderMa,
    this.maxMa = mesozoicYoungerMa,
    this.axis = GeologicTimelineAxis.vertical,
    this.scale = 1.0,
    this.showYearLabels = true,
  });

  /// PBDB-style age bounds: [minAgeMa] is younger, [maxAgeMa] is older.
  const GeologicTimeline.fromAgeRange({
    super.key,
    double? minAgeMa,
    double? maxAgeMa,
    double minMa = mesozoicOlderMa,
    double maxMa = mesozoicYoungerMa,
    GeologicTimelineAxis axis = GeologicTimelineAxis.vertical,
    double scale = 1.0,
    this.showYearLabels = true,
  }) : birth = maxAgeMa,
       death = minAgeMa,
       minMa = minMa,
       maxMa = maxMa,
       axis = axis,
       scale = scale;

  static const double mesozoicOlderMa = timeline_constants.mesozoicOlderMa;
  static const double mesozoicYoungerMa = timeline_constants.mesozoicYoungerMa;

  final double? birth;
  final double? death;
  final double minMa;
  final double maxMa;
  final GeologicTimelineAxis axis;
  final double scale;
  final bool showYearLabels;

  static const _periods = [
    _PeriodRange('Triassic', startMa: 252, endMa: 201),
    _PeriodRange('Jurassic', startMa: 201, endMa: 145),
    _PeriodRange('Cretaceous', startMa: 145, endMa: 66),
  ];

  double? _positionForMa(double ma) {
    if (ma < maxMa || ma > minMa) return null;
    return (ma - maxMa) / (minMa - maxMa);
  }

  @override
  Widget build(BuildContext context) {
    final rangeStart = birth ?? death;
    final rangeEnd = death ?? birth;
    final startPos = rangeStart != null ? _positionForMa(rangeStart) : null;
    final endPos = rangeEnd != null ? _positionForMa(rangeEnd) : null;
    final sameMa = birth != null && death != null && birth == death;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (axis == GeologicTimelineAxis.horizontal) {
          return _HorizontalTimeline(
            cardTheme: DinoCardTheme.of(context),
            scale: scale,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            startPos: startPos,
            endPos: endPos,
            sameMa: sameMa,
            minMa: minMa,
            maxMa: maxMa,
            positionForMa: _positionForMa,
            showYearLabels: showYearLabels,
          );
        }
        return _VerticalTimeline(
          cardTheme: DinoCardTheme.of(context),
          scale: scale,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          startPos: startPos,
          endPos: endPos,
          sameMa: sameMa,
          positionForMa: _positionForMa,
        );
      },
    );
  }
}

class _VerticalTimeline extends StatelessWidget {
  const _VerticalTimeline({
    required this.cardTheme,
    required this.scale,
    required this.width,
    required this.height,
    required this.startPos,
    required this.endPos,
    required this.sameMa,
    required this.positionForMa,
  });

  final DinoCardTheme cardTheme;
  final double scale;
  final double width;
  final double height;
  final double? startPos;
  final double? endPos;
  final bool sameMa;
  final double? Function(double ma) positionForMa;

  static const _boundaryMas = [252.0, 201.0, 145.0, 66.0];

  double get _axisLeft => 28 * scale;
  double get _barWidth => 6 * scale;
  double get _rangeWidth => 12 * scale;
  double get _minRangeExtent => 10 * scale;
  double get _dotSize => 12 * scale;
  double get _labelFontSize => 8.5 * scale;
  double get _labelDotSize => 5 * scale;
  double get _labelGap => 6 * scale;
  double get _maLabelFontSize => 8 * scale;
  double get _maLabelWidth => 34 * scale;

  double _yForMa(double ma) {
    final pos = positionForMa(ma)!;
    return (1 - pos.clamp(0.0, 1.0)) * height;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < GeologicTimeline._periods.length; i++)
            Positioned(
              left: _axisLeft,
              top: _yForMa(GeologicTimeline._periods[i].startMa),
              bottom: height - _yForMa(GeologicTimeline._periods[i].endMa),
              child: Container(
                width: _barWidth,
                decoration: BoxDecoration(
                  color: _pinColor(
                    GeologicTimeline._periods[i].name,
                  ).withValues(alpha: 0.78),
                  borderRadius: BorderRadius.vertical(
                    top: i == 0 ? const Radius.circular(2) : Radius.zero,
                    bottom: i == GeologicTimeline._periods.length - 1
                        ? const Radius.circular(2)
                        : Radius.zero,
                  ),
                ),
              ),
            ),
          if (sameMa && startPos != null)
            Positioned(
              left: _axisLeft - (_rangeWidth - _barWidth) / 2,
              top:
                  (1 - startPos!.clamp(0.0, 1.0)) * height -
                  _minRangeExtent / 2,
              child: Container(
                width: _rangeWidth,
                height: _minRangeExtent,
                decoration: BoxDecoration(
                  color: cardTheme.cardTextPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cardTheme.cardTextPrimary.withValues(alpha: 0.55),
                  ),
                ),
              ),
            )
          else if (startPos != null && endPos != null)
            Positioned(
              left: _axisLeft - (_rangeWidth - _barWidth) / 2,
              top: (1 - startPos!.clamp(0.0, 1.0)) * height,
              bottom: endPos!.clamp(0.0, 1.0) * height,
              child: Container(
                width: _rangeWidth,
                decoration: BoxDecoration(
                  color: cardTheme.cardTextPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cardTheme.cardTextPrimary.withValues(alpha: 0.55),
                  ),
                ),
              ),
            )
          else if (startPos != null)
            Positioned(
              left: _axisLeft - (_dotSize - _barWidth) / 2,
              top: (1 - startPos!.clamp(0.0, 1.0)) * height - _dotSize / 2,
              child: _TimelineDot(
                scale: scale,
                color: cardTheme.cardTextPrimary,
                borderColor: cardTheme.cardTextPrimary,
              ),
            ),
          for (final period in GeologicTimeline._periods)
            Positioned(
              top: _yForMa(period.midMa) - 8 * scale,
              left: 0,
              width: _axisLeft - 4 * scale,
              child: _VerticalPeriodLabel(
                name: period.name,
                cardTheme: cardTheme,
                fontSize: _labelFontSize,
                dotSize: _labelDotSize,
                gap: _labelGap,
              ),
            ),
          for (final ma in _boundaryMas)
            Positioned(
              left: _axisLeft + _barWidth + 4 * scale,
              top: _yForMa(ma) - 7 * scale,
              width: _maLabelWidth,
              child: Text(
                '${ma.round()} Ma',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: cardTheme.timelineAnnotationColor(),
                  fontSize: _maLabelFontSize,
                  height: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HorizontalTimeline extends StatelessWidget {
  const _HorizontalTimeline({
    required this.cardTheme,
    required this.scale,
    required this.width,
    required this.height,
    required this.startPos,
    required this.endPos,
    required this.sameMa,
    required this.minMa,
    required this.maxMa,
    required this.positionForMa,
    required this.showYearLabels,
  });

  final DinoCardTheme cardTheme;
  final double scale;
  final double width;
  final double height;
  final double? startPos;
  final double? endPos;
  final bool sameMa;
  final double minMa;
  final double maxMa;
  final double? Function(double ma) positionForMa;
  final bool showYearLabels;

  static const _boundaryMas = [252.0, 201.0, 145.0, 66.0];

  double get _horizontalInset => 14.0 * scale;
  double get _periodLabelHeight => 12.0 * scale;
  double get _labelToBarGap => 4.0 * scale;
  double get _barHeight => 8.0 * scale;
  double get _rangeIndicatorHeight => 16.0 * scale;
  double get _barToMaGap => 4.0 * scale;
  double get _maLabelHeight => 11.0 * scale;
  double get _knobSize => 14.0 * scale;

  /// Full visual stack height (period labels → bar → Ma labels).
  double get _contentHeight =>
      _periodLabelHeight +
      _labelToBarGap +
      _rangeIndicatorHeight +
      _barToMaGap +
      _maLabelHeight;

  double _xForMa(double ma, double trackWidth) {
    final pos = positionForMa(ma)!;
    return _horizontalInset + (1 - pos.clamp(0.0, 1.0)) * trackWidth;
  }

  /// Gold knob sits on the middle of the taxon's range.
  double? _knobCenterX(double trackWidth) {
    if (startPos == null && endPos == null) return null;
    if (sameMa && startPos != null) {
      return _horizontalInset + (1 - startPos!.clamp(0.0, 1.0)) * trackWidth;
    }
    final older = startPos ?? endPos!;
    final younger = endPos ?? startPos!;
    final mid = ((older + younger) / 2).clamp(0.0, 1.0);
    return _horizontalInset + (1 - mid) * trackWidth;
  }

  /// Left→right fraction for an age (older left). Matches Ma tick positions.
  double _leftFractionForMa(double ma) {
    final span = minMa - maxMa;
    if (span <= 0) return 0;
    return ((minMa - ma) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final trackWidth = width - _horizontalInset * 2;
    final y0 = ((height - _contentHeight) / 2).clamp(0.0, height);
    final periodTop = y0;
    final barBandTop = y0 + _periodLabelHeight + _labelToBarGap;
    final barTop = barBandTop + (_rangeIndicatorHeight - _barHeight) / 2;
    final maTop = barBandTop + _rangeIndicatorHeight + _barToMaGap;

    // Soft fades centered on Triassic/Jurassic (201) and Jurassic/Cretaceous (145).
    final t201 = _leftFractionForMa(201);
    final t145 = _leftFractionForMa(145);
    // ~±8 Ma blend width on the 252→66 Ma track.
    final blend = (8.0 / (minMa - maxMa)).clamp(0.02, 0.08);
    final triassic = _pinColor('triassic');
    final jurassic = _pinColor('jurassic');
    final cretaceous = _pinColor('cretaceous');

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: _horizontalInset,
            top: barTop,
            width: trackWidth,
            height: _barHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                // Left = older (Triassic) → right = younger (Cretaceous),
                // same hues as map period pins; soft fades at 201 & 145 Ma.
                gradient: LinearGradient(
                  colors: [
                    triassic,
                    triassic,
                    jurassic,
                    jurassic,
                    cretaceous,
                    cretaceous,
                  ],
                  stops: [
                    0.0,
                    (t201 - blend).clamp(0.0, 1.0),
                    (t201 + blend).clamp(0.0, 1.0),
                    (t145 - blend).clamp(0.0, 1.0),
                    (t145 + blend).clamp(0.0, 1.0),
                    1.0,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: jurassic.withValues(alpha: 0.35),
                    blurRadius: 6,
                    spreadRadius: 0.2,
                  ),
                ],
              ),
            ),
          ),
          if (_knobCenterX(trackWidth) != null)
            Positioned(
              left: _knobCenterX(trackWidth)! - _knobSize / 2,
              top: barTop + (_barHeight - _knobSize) / 2,
              child: Container(
                width: _knobSize,
                height: _knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF6E2A8),
                  border: Border.all(color: const Color(0xFF8A6424), width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xCCC5944E),
                      blurRadius: 8,
                      spreadRadius: 0.6,
                    ),
                  ],
                ),
              ),
            ),
          if (showYearLabels)
            for (final ma in _boundaryMas)
              Positioned(
                left: ma == minMa
                    ? _horizontalInset - 2 * scale
                    : ma == maxMa
                    ? null
                    : _xForMa(ma, trackWidth) - 24 * scale,
                right: ma == maxMa ? _horizontalInset - 2 * scale : null,
                top: maTop,
                width: ma == minMa || ma == maxMa ? null : 48 * scale,
                child: Text(
                  '${ma.round()} Ma',
                  textAlign: ma == maxMa
                      ? TextAlign.right
                      : ma == minMa
                      ? TextAlign.left
                      : TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: DinoCardTheme.titleFontFamily,
                    color: cardTheme.timelineAnnotationColor(),
                    fontSize: 9 * scale,
                    height: 1.1,
                  ),
                ),
              ),
          for (final period in GeologicTimeline._periods)
            Positioned(
              left: _xForMa(period.midMa, trackWidth) - 32 * scale,
              top: periodTop,
              width: 64 * scale,
              height: _periodLabelHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _HorizontalPeriodLabel(
                  name: period.name,
                  cardTheme: cardTheme,
                  fontSize: 10 * scale,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodRange {
  const _PeriodRange(this.name, {required this.startMa, required this.endMa});

  final String name;
  final double startMa;
  final double endMa;

  double get midMa => (startMa + endMa) / 2;
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({
    this.scale = 1.0,
    required this.color,
    required this.borderColor,
  });

  final double scale;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final size = 12.0 * scale;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: borderColor, width: 1),
      ),
    );
  }
}

class _VerticalPeriodLabel extends StatelessWidget {
  const _VerticalPeriodLabel({
    required this.name,
    required this.cardTheme,
    required this.fontSize,
    required this.dotSize,
    required this.gap,
  });

  final String name;
  final DinoCardTheme cardTheme;
  final double fontSize;
  final double dotSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: cardTheme.periodLabelColor(),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: gap),
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cardTheme.cardAccent.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _HorizontalPeriodLabel extends StatelessWidget {
  const _HorizontalPeriodLabel({
    required this.name,
    required this.cardTheme,
    required this.fontSize,
  });

  final String name;
  final DinoCardTheme cardTheme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: DinoCardTheme.titleFontFamily,
        color: cardTheme.periodLabelColor(),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
