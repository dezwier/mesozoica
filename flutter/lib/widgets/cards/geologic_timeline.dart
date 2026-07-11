import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

enum GeologicTimelineAxis { vertical, horizontal }

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
  });

  static const double mesozoicOlderMa = 252;
  static const double mesozoicYoungerMa = 66;

  final double? birth;
  final double? death;
  final double minMa;
  final double maxMa;
  final GeologicTimelineAxis axis;
  final double scale;

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
          );
        }
        return _VerticalTimeline(
          cardTheme: DinoCardTheme.of(context),
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
    required this.width,
    required this.height,
    required this.startPos,
    required this.endPos,
    required this.sameMa,
    required this.positionForMa,
  });

  final DinoCardTheme cardTheme;
  final double width;
  final double height;
  final double? startPos;
  final double? endPos;
  final bool sameMa;
  final double? Function(double ma) positionForMa;

  static const _minRangeExtent = 10.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 32,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cardTheme.cardAccent.withValues(alpha: 0.35),
                    cardTheme.cardAccent,
                    cardTheme.cardAccent.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          if (sameMa && startPos != null)
            Positioned(
              left: 28,
              top: (1 - startPos!.clamp(0.0, 1.0)) * height - _minRangeExtent / 2,
              child: Container(
                width: 11,
                height: _minRangeExtent,
                decoration: BoxDecoration(
                  color: cardTheme.cardAccent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cardTheme.cardAccent.withValues(alpha: 0.7),
                  ),
                ),
              ),
            )
          else if (startPos != null && endPos != null)
            Positioned(
              left: 28,
              top: (1 - startPos!.clamp(0.0, 1.0)) * height,
              bottom: endPos!.clamp(0.0, 1.0) * height,
              child: Container(
                width: 11,
                decoration: BoxDecoration(
                  color: cardTheme.cardAccent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: cardTheme.cardAccent.withValues(alpha: 0.7),
                  ),
                ),
              ),
            )
          else if (startPos != null)
            Positioned(
              left: 27,
              top: (1 - startPos!.clamp(0.0, 1.0)) * height - 5,
              child: _TimelineDot(
                color: cardTheme.cardAccent,
                borderColor: cardTheme.cardTextPrimary,
              ),
            ),
          for (final period in GeologicTimeline._periods)
            Positioned(
              top: (1 - positionForMa(period.midMa)!.clamp(0.0, 1.0)) * height -
                  10,
              left: 0,
              right: 0,
              child: _VerticalPeriodLabel(
                name: period.name,
                cardTheme: cardTheme,
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

  static const _boundaryMas = [252.0, 201.0, 145.0, 66.0];

  double get _horizontalInset => 14.0 * scale;
  double get _barTop => 30.0 * scale;
  double get _barHeight => 6.0 * scale;
  double get _minRangeWidth => 12.0 * scale;
  double get _rangeIndicatorHeight => 14.0 * scale;

  double _xForMa(double ma, double trackWidth) {
    final pos = positionForMa(ma)!;
    return _horizontalInset + (1 - pos.clamp(0.0, 1.0)) * trackWidth;
  }

  @override
  Widget build(BuildContext context) {
    final trackWidth = width - _horizontalInset * 2;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < GeologicTimeline._periods.length; i++)
            Positioned(
              left: _xForMa(GeologicTimeline._periods[i].startMa, trackWidth),
              top: _barTop,
              width: _xForMa(GeologicTimeline._periods[i].endMa, trackWidth) -
                  _xForMa(GeologicTimeline._periods[i].startMa, trackWidth),
              child: Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  color: cardTheme.cardAccent
                      .withValues(alpha: 0.28 + i * 0.12),
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(2) : Radius.zero,
                    right: i == GeologicTimeline._periods.length - 1
                        ? const Radius.circular(2)
                        : Radius.zero,
                  ),
                ),
              ),
            ),
          if (sameMa && startPos != null)
            Positioned(
              left: _horizontalInset +
                  (1 - startPos!.clamp(0.0, 1.0)) * trackWidth -
                  _minRangeWidth / 2,
              top: _barTop - (_rangeIndicatorHeight - _barHeight) / 2,
              width: _minRangeWidth,
              child: Container(
                height: _rangeIndicatorHeight,
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
              left: _horizontalInset +
                  (1 - startPos!.clamp(0.0, 1.0)) * trackWidth,
              top: _barTop - (_rangeIndicatorHeight - _barHeight) / 2,
              width: ((startPos! - endPos!).clamp(0.0, 1.0)) * trackWidth,
              child: Container(
                height: _rangeIndicatorHeight,
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
              left: _horizontalInset +
                  (1 - startPos!.clamp(0.0, 1.0)) * trackWidth -
                  5 * scale,
              top: _barTop - (_rangeIndicatorHeight - _barHeight) / 2,
              child: _TimelineDot(
                scale: scale,
                color: cardTheme.cardTextPrimary,
                borderColor: cardTheme.cardTextPrimary,
              ),
            ),
          for (final ma in _boundaryMas)
            Positioned(
              left: ma == minMa
                  ? _horizontalInset - 2 * scale
                  : ma == maxMa
                      ? null
                      : _xForMa(ma, trackWidth) - 16 * scale,
              right: ma == maxMa ? _horizontalInset - 2 * scale : null,
              top: _barTop + _barHeight + 4 * scale,
              width: ma == minMa || ma == maxMa ? null : 32 * scale,
              child: Text(
                '${ma.round()} Ma',
                textAlign: ma == maxMa
                    ? TextAlign.right
                    : ma == minMa
                        ? TextAlign.left
                        : TextAlign.center,
                style: TextStyle(
                  color: cardTheme.timelineAnnotationColor(),
                  fontSize: 9 * scale,
                ),
              ),
            ),
          for (final period in GeologicTimeline._periods)
            Positioned(
              left: _xForMa(period.midMa, trackWidth) - 32 * scale,
              top: 8 * scale,
              width: 64 * scale,
              child: _HorizontalPeriodLabel(
                name: period.name,
                cardTheme: cardTheme,
                fontSize: 10 * scale,
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
  });

  final String name;
  final DinoCardTheme cardTheme;

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
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 6,
          height: 6,
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
        color: cardTheme.periodLabelColor(),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
