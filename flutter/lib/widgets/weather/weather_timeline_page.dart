import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/weather_forecast.dart';
import '../../theme/map_chrome_theme.dart';
import 'weather_display.dart';

/// Past or forecast hourly timeline: temp curve + weather-type ticks on parchment.
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
  });

  final String title;
  final List<WeatherHourPoint> hours;
  final bool loading;
  final String emptyHint;

  @override
  State<WeatherTimelinePage> createState() => _WeatherTimelinePageState();
}

class _WeatherTimelinePageState extends State<WeatherTimelinePage> {
  int? _hoverIndex;

  @override
  void didUpdateWidget(covariant WeatherTimelinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hours != widget.hours) {
      _hoverIndex = null;
    }
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

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: MapChromeTheme.labelMuted,
          fontSize: 14,
        );
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: MapChromeTheme.brownText,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        );
    final hovered =
        (_hoverIndex != null && _hoverIndex! < hours.length)
            ? hours[_hoverIndex!]
            : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: MapChromeTheme.parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MapChromeTheme.chromeBorder,
          width: MapChromeTheme.chromeBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: MapChromeTheme.leather.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.title, style: titleStyle)),
                if (hovered != null)
                  Flexible(
                    child: Text(
                      '${WeatherDisplay.weatherLabel(hovered.weatherType)}'
                      ' · ${hovered.temperatureC.round()}°'
                      ' · ${DateFormat('EEE HH:mm').format(hovered.validAt.toLocal())}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: MapChromeTheme.labelMuted,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
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
                                  selectedIndex: _hoverIndex,
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
    this.selectedIndex,
  });

  final List<WeatherHourPoint> hours;
  final int? selectedIndex;

  static const leftPad = 30.0;
  static const rightPad = 8.0;
  static const _topPad = 10.0;
  static const _bottomPad = 24.0;

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

    var minT = hours.first.temperatureC;
    var maxT = hours.first.temperatureC;
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

    _drawGrid(canvas, chart);
    _drawTempFillAndLine(canvas, chart, minT, maxT);
    _drawWeatherTicks(canvas, chart, minT, maxT);
    if (selectedIndex != null) {
      _drawSelection(canvas, chart, minT, maxT, selectedIndex!);
    }
    _drawAxes(canvas, chart, minT, maxT);
  }

  Offset _pointAt(int i, Rect chart, double minT, double maxT) {
    final x = hours.length == 1
        ? chart.center.dx
        : chart.left + (i / (hours.length - 1)) * chart.width;
    final t = hours[i].temperatureC;
    final yNorm = (t - minT) / (maxT - minT);
    final y = chart.bottom - yNorm * chart.height;
    return Offset(x, y);
  }

  void _drawGrid(Canvas canvas, Rect chart) {
    final paint = Paint()
      ..color = MapChromeTheme.parchmentEdge.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), paint);
    }
  }

  void _drawTempFillAndLine(
    Canvas canvas,
    Rect chart,
    double minT,
    double maxT,
  ) {
    final path = Path();
    for (var i = 0; i < hours.length; i++) {
      final p = _pointAt(i, chart, minT, maxT);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(_pointAt(hours.length - 1, chart, minT, maxT).dx, chart.bottom)
      ..lineTo(_pointAt(0, chart, minT, maxT).dx, chart.bottom)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(chart.center.dx, chart.top),
          Offset(chart.center.dx, chart.bottom),
          [
            MapChromeTheme.gold.withValues(alpha: 0.28),
            MapChromeTheme.gold.withValues(alpha: 0.02),
          ],
        ),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = MapChromeTheme.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawWeatherTicks(
    Canvas canvas,
    Rect chart,
    double minT,
    double maxT,
  ) {
    final step = hours.length > 24
        ? 3
        : hours.length > 12
            ? 2
            : 1;
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    for (var i = 0; i < hours.length; i += step) {
      final p = _pointAt(i, chart, minT, maxT);
      final type = hours[i].weatherType;
      final icon = WeatherDisplay.weatherIcon(type);
      final color = WeatherDisplay.weatherIconColor(type);
      canvas.drawCircle(
        Offset(p.dx, chart.bottom + 2),
        3.5,
        Paint()..color = color.withValues(alpha: 0.85),
      );
      tp.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 11,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: MapChromeTheme.brownText.withValues(alpha: 0.75),
        ),
      );
      tp.layout();
      final iconY = math.max(chart.top + 2, p.dy - 16);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, iconY));
    }
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
        ..color = MapChromeTheme.brassMid.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(p, 5.5, Paint()..color = MapChromeTheme.creamCard);
    canvas.drawCircle(p, 4, Paint()..color = MapChromeTheme.goldBright);
  }

  void _drawAxes(Canvas canvas, Rect chart, double minT, double maxT) {
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    const yLabelStyle = TextStyle(
      fontSize: 10,
      color: MapChromeTheme.labelMuted,
      fontWeight: FontWeight.w500,
    );
    for (var i = 0; i <= 3; i++) {
      final t = maxT - (maxT - minT) * i / 3;
      final y = chart.top + chart.height * i / 3;
      tp.text = TextSpan(text: '${t.round()}°', style: yLabelStyle);
      tp.layout();
      tp.paint(canvas, Offset(chart.left - tp.width - 4, y - tp.height / 2));
    }

    const xLabelStyle = TextStyle(
      fontSize: 10,
      color: MapChromeTheme.labelMuted,
      fontWeight: FontWeight.w500,
    );
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
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherTimelinePainter oldDelegate) {
    return oldDelegate.hours != hours ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
