import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/weather_forecast.dart';
import '../../utils/solar_period.dart';
import 'weather_display.dart';

/// Past or forecast timeline (15-min samples): temp curve + weather icons.
///
/// Horizontal drag / tap scrubs the series (page swipes are disabled on the
/// parent [PageView] so gestures stay with the chart).
class WeatherTimelinePage extends StatefulWidget {
  const WeatherTimelinePage({
    super.key,
    required this.title,
    required this.hours,
    required this.loading,
    this.emptyHint = 'Gathering field notes…',
    this.tempMin,
    this.tempMax,
    this.latitude,
    this.longitude,
  });

  final String title;
  final List<WeatherHourPoint> hours;
  final bool loading;
  final String emptyHint;

  /// Shared Y-axis floor/ceiling (e.g. spanning past + forecast). When null,
  /// the range is derived from [hours] alone.
  final double? tempMin;
  final double? tempMax;

  /// Used to pick sun vs moon icons per sample (clear + night/dusk → moon).
  final double? latitude;
  final double? longitude;

  /// Inclusive temp range covering every sample in [series], or null if empty.
  static (double, double)? sharedTempRange(
    Iterable<List<WeatherHourPoint>> series,
  ) {
    var hasAny = false;
    var minT = 0.0;
    var maxT = 0.0;
    for (final hours in series) {
      for (final h in hours) {
        if (!hasAny) {
          minT = h.temperatureC;
          maxT = h.temperatureC;
          hasAny = true;
        } else {
          minT = math.min(minT, h.temperatureC);
          maxT = math.max(maxT, h.temperatureC);
        }
      }
    }
    if (!hasAny) return null;
    if ((maxT - minT).abs() < 1) {
      minT -= 1;
      maxT += 1;
    }
    final pad = (maxT - minT) * 0.12;
    return (minT - pad, maxT + pad);
  }

  @override
  State<WeatherTimelinePage> createState() => _WeatherTimelinePageState();
}

class _WeatherTimelinePageState extends State<WeatherTimelinePage> {
  int? _hoverIndex;

  @override
  void initState() {
    super.initState();
    _hoverIndex = _defaultIndex(widget.hours, widget.title);
  }

  @override
  void didUpdateWidget(covariant WeatherTimelinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hours != widget.hours || oldWidget.title != widget.title) {
      // Keep scrub position when possible; otherwise snap to default "now".
      if (_hoverIndex == null ||
          _hoverIndex! >= widget.hours.length ||
          oldWidget.hours != widget.hours) {
        _hoverIndex = _defaultIndex(widget.hours, widget.title);
      }
    }
  }

  /// Past → latest hour; forecast → soonest upcoming hour.
  static int? _defaultIndex(List<WeatherHourPoint> hours, String title) {
    if (hours.isEmpty) return null;
    final isPast = title.toLowerCase().contains('past');
    return isPast ? hours.length - 1 : 0;
  }

  void _selectFromDx(double dx, double width) {
    final hours = widget.hours;
    if (hours.isEmpty || width <= 0) return;
    final chartLeft = _WeatherTimelinePainter.leftPad;
    final chartRight = width - _WeatherTimelinePainter.rightPad;
    final chartW = chartRight - chartLeft;
    if (chartW <= 0) return;
    final t = ((dx - chartLeft) / chartW).clamp(0.0, 1.0);
    final index = (t * (hours.length - 1)).round().clamp(0, hours.length - 1);
    if (index != _hoverIndex) {
      setState(() => _hoverIndex = index);
    }
  }

  /// Solar period name for icon day/night, or null when lat/lon missing.
  String? _periodAt(DateTime at) {
    final lat = widget.latitude;
    final lon = widget.longitude;
    if (lat == null || lon == null) return null;
    return Solar.periodAt(latitude: lat, longitude: lon, at: at).name;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hours = widget.hours;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: muted,
          fontSize: 14,
        );
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.82),
          fontWeight: FontWeight.w600,
          fontSize: 15,
        );
    final selectedIndex =
        (_hoverIndex != null && _hoverIndex! < hours.length)
            ? _hoverIndex!
            : _defaultIndex(hours, widget.title);
    final hovered =
        selectedIndex != null ? hours[selectedIndex] : null;
    final hoveredPeriod =
        hovered != null ? _periodAt(hovered.validAt) : null;

    final radius = BorderRadius.circular(10);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: radius,
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(widget.title, style: titleStyle),
                if (hovered != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            WeatherDisplay.weatherIcon(
                              hovered.weatherType,
                              weatherTime: hoveredPeriod,
                            ),
                            size: 15,
                            color: WeatherDisplay.weatherIconColor(
                              hovered.weatherType,
                              weatherTime: hoveredPeriod,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${WeatherDisplay.weatherLabel(hovered.weatherType)}'
                            ' · ${hovered.temperatureC.round()}°'
                            ' · ${DateFormat('EEE HH:mm').format(hovered.validAt.toLocal())}',
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.loading && hours.isEmpty
                  ? Center(child: Text(widget.emptyHint, style: bodyStyle))
                  : hours.isEmpty
                      ? Center(
                          child: Text(
                            widget.emptyHint,
                            textAlign: TextAlign.center,
                            style: bodyStyle,
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                              ),
                              onHorizontalDragStart: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                              ),
                              onHorizontalDragUpdate: (d) => _selectFromDx(
                                d.localPosition.dx,
                                constraints.maxWidth,
                              ),
                              child: CustomPaint(
                                size: Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                ),
                                painter: _WeatherTimelinePainter(
                                  hours: hours,
                                  selectedIndex: selectedIndex,
                                  tempMin: widget.tempMin,
                                  tempMax: widget.tempMax,
                                  latitude: widget.latitude,
                                  longitude: widget.longitude,
                                  lineColor: scheme.onSurface
                                      .withValues(alpha: 0.55),
                                  fillTop: scheme.onSurface
                                      .withValues(alpha: 0.12),
                                  fillBottom: scheme.onSurface
                                      .withValues(alpha: 0.0),
                                  gridColor: scheme.outlineVariant
                                      .withValues(alpha: 0.55),
                                  axisColor: scheme.onSurface
                                      .withValues(alpha: 0.45),
                                  midnightColor: scheme.onSurface
                                      .withValues(alpha: 0.28),
                                  selectionColor: scheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherTimelinePainter extends CustomPainter {
  _WeatherTimelinePainter({
    required this.hours,
    required this.lineColor,
    required this.fillTop,
    required this.fillBottom,
    required this.gridColor,
    required this.axisColor,
    required this.midnightColor,
    required this.selectionColor,
    this.selectedIndex,
    this.tempMin,
    this.tempMax,
    this.latitude,
    this.longitude,
  });

  final List<WeatherHourPoint> hours;
  final int? selectedIndex;
  final double? tempMin;
  final double? tempMax;
  final double? latitude;
  final double? longitude;
  final Color lineColor;
  final Color fillTop;
  final Color fillBottom;
  final Color gridColor;
  final Color axisColor;
  final Color midnightColor;
  final Color selectionColor;

  static const leftPad = 30.0;
  static const rightPad = 8.0;
  static const _topPad = 8.0;
  /// Room for weather icons + time labels under the plot.
  static const _bottomPad = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.isEmpty) return;

    final chart = Rect.fromLTRB(
      leftPad,
      _topPad,
      size.width - rightPad,
      size.height - _bottomPad,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    double minT;
    double maxT;
    final sharedMin = tempMin;
    final sharedMax = tempMax;
    if (sharedMin != null && sharedMax != null && sharedMax > sharedMin) {
      minT = sharedMin;
      maxT = sharedMax;
    } else {
      minT = hours.first.temperatureC;
      maxT = hours.first.temperatureC;
      for (final h in hours) {
        minT = math.min(minT, h.temperatureC);
        maxT = math.max(maxT, h.temperatureC);
      }
      if ((maxT - minT).abs() < 1) {
        minT -= 1;
        maxT += 1;
      }
      final pad = (maxT - minT) * 0.12;
      minT -= pad;
      maxT += pad;
    }

    _drawGrid(canvas, chart);
    _drawMidnightMarkers(canvas, chart);
    _drawTempFillAndLine(canvas, chart, minT, maxT);
    if (selectedIndex != null) {
      _drawSelection(canvas, chart, minT, maxT, selectedIndex!);
    }
    _drawYAxis(canvas, chart, minT, maxT);
    _drawXAxisIconsAndLabels(canvas, chart);
  }

  Offset _pointAt(int i, Rect chart, double minT, double maxT, [double? tempC]) {
    final x = hours.length == 1
        ? chart.center.dx
        : chart.left + (i / (hours.length - 1)) * chart.width;
    final t = tempC ?? hours[i].temperatureC;
    final yNorm = (t - minT) / (maxT - minT);
    final y = chart.bottom - yNorm * chart.height;
    return Offset(x, y);
  }

  /// Light moving average so the 15-min series doesn't look jagged.
  List<double> _smoothedTemps() {
    final raw = [for (final h in hours) h.temperatureC];
    if (raw.length < 5) return raw;
    const radius = 2; // 5-sample window (~1h at 15-min cadence)
    return [
      for (var i = 0; i < raw.length; i++)
        () {
          var sum = 0.0;
          var n = 0;
          for (var j = i - radius; j <= i + radius; j++) {
            if (j >= 0 && j < raw.length) {
              sum += raw[j];
              n++;
            }
          }
          return sum / n;
        }(),
    ];
  }

  /// Catmull-Rom spline through [points] (smoother than mid-point cubics).
  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _drawGrid(Canvas canvas, Rect chart) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
  }

  void _drawMidnightMarkers(Canvas canvas, Rect chart) {
    final paint = Paint()
      ..color = midnightColor
      ..strokeWidth = 1.1;
    final labelStyle = TextStyle(
      fontSize: 9,
      color: axisColor,
      fontWeight: FontWeight.w600,
    );
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < hours.length; i++) {
      final local = hours[i].validAt.toLocal();
      // Only the :00 slot — 15-min series has four points in hour 0.
      if (local.hour != 0 || local.minute != 0) continue;
      final x = hours.length == 1
          ? chart.center.dx
          : chart.left + (i / (hours.length - 1)) * chart.width;
      // Dashed vertical midnight line.
      const dash = 4.0;
      const gap = 3.0;
      var y = chart.top;
      while (y < chart.bottom) {
        final y2 = math.min(y + dash, chart.bottom);
        canvas.drawLine(Offset(x, y), Offset(x, y2), paint);
        y = y2 + gap;
      }
      final day = DateFormat('E').format(local);
      tp.text = TextSpan(text: day, style: labelStyle);
      tp.layout();
      tp.paint(canvas, Offset(x + 3, chart.top + 2));
    }
  }

  void _drawTempFillAndLine(
    Canvas canvas,
    Rect chart,
    double minT,
    double maxT,
  ) {
    final temps = _smoothedTemps();
    final points = [
      for (var i = 0; i < hours.length; i++)
        _pointAt(i, chart, minT, maxT, temps[i]),
    ];
    final line = _smoothPath(points);
    final fill = Path.from(line)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(chart.center.dx, chart.top),
          Offset(chart.center.dx, chart.bottom),
          [fillTop, fillBottom],
        ),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  void _drawSelection(
    Canvas canvas,
    Rect chart,
    double minT,
    double maxT,
    int index,
  ) {
    final i = index.clamp(0, hours.length - 1);
    final p = _pointAt(i, chart, minT, maxT);
    canvas.drawLine(
      Offset(p.dx, chart.top),
      Offset(p.dx, chart.bottom),
      Paint()
        ..color = selectionColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      p,
      5,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      p,
      3.5,
      Paint()..color = selectionColor,
    );
  }

  void _drawYAxis(Canvas canvas, Rect chart, double minT, double maxT) {
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    final yLabelStyle = TextStyle(
      fontSize: 10,
      color: axisColor,
      fontWeight: FontWeight.w500,
    );
    for (var i = 0; i <= 3; i++) {
      final t = maxT - (maxT - minT) * i / 3;
      final y = chart.top + chart.height * i / 3;
      tp.text = TextSpan(text: '${t.round()}°', style: yLabelStyle);
      tp.layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, y - tp.height / 2));
    }
  }

  void _drawXAxisIconsAndLabels(Canvas canvas, Rect chart) {
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    final xLabelStyle = TextStyle(
      fontSize: 9,
      color: axisColor,
      fontWeight: FontWeight.w500,
    );

    // Icons every 3 clock hours (15-min series would otherwise be too dense).
    for (var i = 0; i < hours.length; i++) {
      final local = hours[i].validAt.toLocal();
      if (local.minute != 0 || local.hour % 3 != 0) continue;
      final x = hours.length == 1
          ? chart.center.dx
          : chart.left + (i / (hours.length - 1)) * chart.width;
      final type = hours[i].weatherType;
      final lat = latitude;
      final lon = longitude;
      final period = (lat != null && lon != null)
          ? Solar.periodAt(
              latitude: lat,
              longitude: lon,
              at: hours[i].validAt,
            ).name
          : null;
      final icon = WeatherDisplay.weatherIcon(type, weatherTime: period);
      final color = WeatherDisplay.weatherIconColor(type, weatherTime: period);
      tp.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 13,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 3));
    }

    // Time labels under the icon row.
    final span = hours.last.validAt.difference(hours.first.validAt);
    final multiDay = span.inHours >= 30;
    final labelCount = math.min(5, hours.length);
    for (var i = 0; i < labelCount; i++) {
      final index = labelCount == 1
          ? 0
          : ((hours.length - 1) * i / (labelCount - 1)).round();
      final local = hours[index].validAt.toLocal();
      final label = multiDay
          ? DateFormat('E HH').format(local)
          : DateFormat('HH').format(local);
      final x = hours.length == 1
          ? chart.center.dx
          : chart.left + (index / (hours.length - 1)) * chart.width;
      tp.text = TextSpan(text: label, style: xLabelStyle);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 20));
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherTimelinePainter oldDelegate) {
    return oldDelegate.hours != hours ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.tempMin != tempMin ||
        oldDelegate.tempMax != tempMax ||
        oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillTop != fillTop ||
        oldDelegate.gridColor != gridColor;
  }
}
