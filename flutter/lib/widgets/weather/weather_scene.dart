import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'weather_display.dart';

/// Illustrated weather type (day/night art) with optional particle motion.
class WeatherScene extends StatefulWidget {
  const WeatherScene({
    super.key,
    required this.weatherType,
    required this.weatherTime,
    this.size = 160,
    this.circular = false,
  });

  final String weatherType;
  final String weatherTime;
  final double size;

  /// Circular avatar crop for the weather drawer hero.
  final bool circular;

  @override
  State<WeatherScene> createState() => _WeatherSceneState();
}

class _WeatherSceneState extends State<WeatherScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (_needsMotion(widget.weatherType) && !widget.circular) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WeatherScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final typeChanged = oldWidget.weatherType != widget.weatherType;
    if (!typeChanged && oldWidget.weatherTime == widget.weatherTime) return;
    if (_needsMotion(widget.weatherType) && !widget.circular) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static bool _needsMotion(String type) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'drizzle':
      case 'rain':
      case 'snow':
      case 'hail':
      case 'thunderstorm':
      case 'fog':
      case 'cloudy':
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = WeatherDisplay.assetPath(
      widget.weatherType,
      weatherTime: widget.weatherTime,
    );
    final showParticles =
        !widget.circular && _needsMotion(widget.weatherType);

    Widget image;
    if (asset != null) {
      image = Image.asset(
        asset,
        fit: widget.circular ? BoxFit.cover : BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _FallbackGlyph(
          weatherType: widget.weatherType,
        ),
      );
    } else {
      image = _FallbackGlyph(weatherType: widget.weatherType);
    }

    final scene = Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        image,
        if (showParticles)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _WeatherParticlePainter(
                  weatherType: widget.weatherType,
                  t: _controller.value,
                ),
              );
            },
          ),
      ],
    );

    if (!widget.circular) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: scene,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(child: scene),
    );
  }
}

class _FallbackGlyph extends StatelessWidget {
  const _FallbackGlyph({required this.weatherType});

  final String weatherType;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Icon(
        WeatherDisplay.weatherIcon(weatherType),
        size: 72,
        color: scheme.primary,
      ),
    );
  }
}

class _WeatherParticlePainter extends CustomPainter {
  _WeatherParticlePainter({
    required this.weatherType,
    required this.t,
  });

  final String weatherType;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final type = weatherType == 'sunny' ? 'clear' : weatherType;
    switch (type) {
      case 'drizzle':
        _paintRain(
          canvas,
          size,
          count: 28,
          length: 8,
          thickness: 1.1,
          speed: 1.2,
        );
        break;
      case 'rain':
        _paintRain(
          canvas,
          size,
          count: 48,
          length: 14,
          thickness: 1.6,
          speed: 1.8,
        );
        break;
      case 'thunderstorm':
        _paintRain(
          canvas,
          size,
          count: 42,
          length: 16,
          thickness: 1.8,
          speed: 2.0,
        );
        _paintLightning(canvas, size);
        break;
      case 'snow':
        _paintSnow(canvas, size, count: 36, maxR: 2.8);
        break;
      case 'hail':
        _paintHail(canvas, size, count: 30);
        break;
      case 'fog':
        _paintFog(canvas, size);
        break;
      case 'cloudy':
        _paintCloudDrift(canvas, size);
        break;
      default:
        break;
    }
  }

  void _paintRain(
    Canvas canvas,
    Size size, {
    required int count,
    required double length,
    required double thickness,
    required double speed,
  }) {
    final paint = Paint()
      ..color = const Color(0x88A8C8E0)
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final seed = i * 17.13;
      final x = ((seed * 37.1) % size.width + size.width) % size.width;
      final cycle = (t * speed + seed * 0.07) % 1.0;
      final y = cycle * (size.height + length) - length;
      canvas.drawLine(Offset(x, y), Offset(x - 2, y + length), paint);
    }
  }

  void _paintSnow(Canvas canvas, Size size, {required int count, required double maxR}) {
    final paint = Paint()..color = const Color(0xCCFFFFFF);
    for (var i = 0; i < count; i++) {
      final seed = i * 23.7;
      final drift = math.sin((t + seed) * math.pi * 2) * 8;
      final x =
          (((seed * 41.3) % size.width) + drift + size.width) % size.width;
      final cycle = (t * 0.55 + seed * 0.05) % 1.0;
      final y = cycle * (size.height + 10) - 5;
      final r = 1.2 + (seed % 7) * 0.25;
      canvas.drawCircle(Offset(x, y), r.clamp(1.0, maxR), paint);
    }
  }

  void _paintHail(Canvas canvas, Size size, {required int count}) {
    final paint = Paint()..color = const Color(0xBBD8E8F8);
    for (var i = 0; i < count; i++) {
      final seed = i * 19.1;
      final x = ((seed * 53.9) % size.width + size.width) % size.width;
      final cycle = (t * 1.6 + seed * 0.09) % 1.0;
      final y = cycle * (size.height + 12) - 6;
      final r = 1.8 + (i % 3) * 0.6;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final pulse = (math.sin(t * math.pi * 4).abs() > 0.92) ? 1.0 : 0.0;
    if (pulse <= 0) return;
    final flash = Paint()
      ..color = Color.fromRGBO(255, 250, 210, 0.18 * pulse);
    canvas.drawRect(Offset.zero & size, flash);
    final bolt = Paint()
      ..color = Color.fromRGBO(255, 245, 180, 0.85 * pulse)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.58, size.height * 0.12)
      ..lineTo(size.width * 0.48, size.height * 0.38)
      ..lineTo(size.width * 0.56, size.height * 0.40)
      ..lineTo(size.width * 0.42, size.height * 0.72);
    canvas.drawPath(path, bolt);
  }

  void _paintFog(Canvas canvas, Size size) {
    for (var band = 0; band < 3; band++) {
      final shift = math.sin((t + band * 0.33) * math.pi * 2) * 18;
      final paint = Paint()
        ..color = Color.fromRGBO(200, 205, 210, 0.12 + band * 0.03);
      final y = size.height * (0.35 + band * 0.18);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5 + shift, y),
          width: size.width * 1.2,
          height: size.height * 0.22,
        ),
        paint,
      );
    }
  }

  void _paintCloudDrift(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x12FFFFFF);
    final shift = math.sin(t * math.pi * 2) * 10;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.35 + shift, size.height * 0.4),
        width: size.width * 0.55,
        height: size.height * 0.22,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.7 - shift * 0.6, size.height * 0.5),
        width: size.width * 0.5,
        height: size.height * 0.2,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _WeatherParticlePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.weatherType != weatherType;
  }
}
