import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vintage field-instrument readout for proximity distance bands.
class ProximityScannerDisplay extends StatelessWidget {
  const ProximityScannerDisplay({
    super.key,
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 168.0 : 248.0;
    final pad = compact ? 10.0 : 14.0;
    final screenPad = compact ? 10.0 : 14.0;
    final titleSize = compact ? 8.0 : 10.0;
    final valueSize = compact ? 22.0 : 34.0;
    final unitSize = compact ? 9.0 : 11.0;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6B6354),
              Color(0xFF3E382E),
              Color(0xFF2A261F),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: const Color(0xFF8A8070), width: 1.2),
        ),
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Rivets(compact: compact),
                  const Spacer(),
                  Text(
                    'PROX·SCAN',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: titleSize,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFC4B89A),
                    ),
                  ),
                  const Spacer(),
                  _Rivets(compact: compact),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),
              _CrtScreen(
                label: label,
                screenPad: screenPad,
                valueSize: valueSize,
                unitSize: unitSize,
                compact: compact,
              ),
              SizedBox(height: compact ? 6 : 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RANGE',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: compact ? 7 : 8,
                      letterSpacing: 1.2,
                      color: const Color(0xFF9A8F78),
                    ),
                  ),
                  Container(
                    width: compact ? 6 : 8,
                    height: compact ? 6 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF7CFF9A).withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7CFF9A).withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'FIELD',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: compact ? 7 : 8,
                      letterSpacing: 1.2,
                      color: const Color(0xFF9A8F78),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rivets extends StatelessWidget {
  const _Rivets({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 5.0 : 6.0;
    Widget rivet() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFFB0A690), Color(0xFF5A5346)],
            ),
            border: Border.all(color: const Color(0xFF2A261F), width: 0.5),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        rivet(),
        SizedBox(width: compact ? 4 : 5),
        rivet(),
      ],
    );
  }
}

class _CrtScreen extends StatelessWidget {
  const _CrtScreen({
    required this.label,
    required this.screenPad,
    required this.valueSize,
    required this.unitSize,
    required this.compact,
  });

  final String label;
  final double screenPad;
  final double valueSize;
  final double unitSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parts = _splitLabel(label);
    return ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 4 : 6),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: screenPad,
              vertical: compact ? 12 : 18,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A1A0C),
                  Color(0xFF061008),
                  Color(0xFF030A04),
                ],
              ),
            ),
            child: Column(
              children: [
                Text(
                  'DIST',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: compact ? 8 : 9,
                    letterSpacing: 2.4,
                    color: const Color(0xFF3D8F4A).withValues(alpha: 0.75),
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  parts.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: valueSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    height: 1.05,
                    color: const Color(0xFF7CFF9A),
                    shadows: [
                      Shadow(
                        color: const Color(0xFF7CFF9A).withValues(alpha: 0.55),
                        blurRadius: 10,
                      ),
                      Shadow(
                        color: const Color(0xFF7CFF9A).withValues(alpha: 0.25),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                ),
                if (parts.unit != null) ...[
                  SizedBox(height: compact ? 2 : 4),
                  Text(
                    parts.unit!,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: unitSize,
                      letterSpacing: 2,
                      color: const Color(0xFF5CB86A).withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinePainter()),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 4 : 6),
                  border: Border.all(
                    color: const Color(0xFF1A3A1E),
                    width: 2,
                  ),
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.95,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ({String value, String? unit}) _splitLabel(String label) {
    final trimmed = label.trim();
    final space = trimmed.lastIndexOf(' ');
    if (space <= 0) return (value: trimmed, unit: null);
    final unit = trimmed.substring(space + 1);
    if (unit == 'm' || unit == 'km') {
      return (value: trimmed.substring(0, space), unit: unit.toUpperCase());
    }
    return (value: trimmed, unit: null);
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7CFF9A).withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Soft horizontal glow band (fake CRT refresh).
    final bandY = size.height * (0.35 + 0.08 * math.sin(size.width));
    canvas.drawRect(
      Rect.fromLTWH(0, bandY, size.width, 10),
      Paint()..color = const Color(0xFF7CFF9A).withValues(alpha: 0.04),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
