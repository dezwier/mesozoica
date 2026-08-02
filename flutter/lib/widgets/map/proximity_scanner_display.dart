import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shell/map_chrome_insets.dart';
import 'vintage_guidance_compass.dart';

/// Vintage field-instrument readout for proximity distance bands.
class ProximityScannerDisplay extends StatelessWidget {
  const ProximityScannerDisplay({
    super.key,
    required this.label,
    this.compact = false,
    this.remaining,
    this.onStop,
  });

  final String label;
  final bool compact;

  /// Remaining session time — shown on the full (non-compact) meter.
  final Duration? remaining;
  final VoidCallback? onStop;

  static const double fullWidth = 148;

  /// Rough laid-out height for stacking other top chrome below the meter.
  static const double mapHeightEstimate = 118;

  @override
  Widget build(BuildContext context) {
    final width = compact ? 132.0 : fullWidth;
    final pad = compact ? 7.0 : 8.0;
    final screenPad = compact ? 8.0 : 9.0;
    final titleSize = compact ? 7.0 : 7.5;
    final valueSize = compact ? 16.0 : 18.0;
    final unitSize = compact ? 8.0 : 8.5;
    final showSessionControls = !compact && onStop != null;

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 8 : 9),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              VintageInstrumentStyle.brassLight,
              VintageInstrumentStyle.brassMid,
              VintageInstrumentStyle.brassDark,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: VintageInstrumentStyle.brassRim,
            width: 1.0,
          ),
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
                    style: VintageInstrumentStyle.mono.copyWith(
                      fontSize: titleSize,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  _Rivets(compact: compact),
                ],
              ),
              const SizedBox(height: 5),
              _CrtScreen(
                label: label,
                screenPad: screenPad,
                valueSize: valueSize,
                unitSize: unitSize,
                compact: compact,
              ),
              const SizedBox(height: 5),
              if (showSessionControls)
                _SessionFooter(
                  remaining: remaining,
                  onStop: onStop!,
                )
              else
                _StatusFooter(compact: compact),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draggable proximity meter; defaults to center-top below archive/field chrome.
class DraggableProximityScanner extends StatefulWidget {
  const DraggableProximityScanner({
    super.key,
    required this.label,
    this.remaining,
    this.onStop,
  });

  final String label;
  final Duration? remaining;
  final VoidCallback? onStop;

  @override
  State<DraggableProximityScanner> createState() =>
      _DraggableProximityScannerState();
}

class _DraggableProximityScannerState extends State<DraggableProximityScanner> {
  Offset _dragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final topClearance = MapChromeInsets.top(context) + 8;
    return Padding(
      padding: EdgeInsets.only(top: topClearance),
      child: Align(
        alignment: Alignment.topCenter,
        child: Transform.translate(
          offset: _dragOffset,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() => _dragOffset += details.delta);
            },
            child: ProximityScannerDisplay(
              label: widget.label,
              remaining: widget.remaining,
              onStop: widget.onStop,
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionFooter extends StatelessWidget {
  const _SessionFooter({
    required this.remaining,
    required this.onStop,
  });

  final Duration? remaining;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final time = formatActiveToolHudRemaining(remaining);
    return Row(
      children: [
        Text(
          time,
          style: VintageInstrumentStyle.mono.copyWith(fontSize: 11),
        ),
        const Spacer(),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: VintageInstrumentStyle.live.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: VintageInstrumentStyle.live.withValues(alpha: 0.55),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onStop,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'STOP',
              style: VintageInstrumentStyle.mono.copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: VintageInstrumentStyle.stop,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFooter extends StatelessWidget {
  const _StatusFooter({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'RANGE',
          style: VintageInstrumentStyle.mono.copyWith(
            fontSize: compact ? 7 : 8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w400,
            color: VintageInstrumentStyle.brassMuted,
          ),
        ),
        Container(
          width: compact ? 6 : 8,
          height: compact ? 6 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: VintageInstrumentStyle.live.withValues(alpha: 0.85),
            boxShadow: [
              BoxShadow(
                color: VintageInstrumentStyle.live.withValues(alpha: 0.55),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        Text(
          'FIELD',
          style: VintageInstrumentStyle.mono.copyWith(
            fontSize: compact ? 7 : 8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w400,
            color: VintageInstrumentStyle.brassMuted,
          ),
        ),
      ],
    );
  }
}

class _Rivets extends StatelessWidget {
  const _Rivets({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 4.5 : 5.0;
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
        SizedBox(width: compact ? 3 : 4),
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
              vertical: compact ? 8 : 9,
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
                SizedBox(height: compact ? 2 : 3),
                Text(
                  parts.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: valueSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    height: 1.05,
                    color: const Color(0xFF7CFF9A),
                    shadows: [
                      Shadow(
                        color: const Color(0xFF7CFF9A).withValues(alpha: 0.55),
                        blurRadius: 8,
                      ),
                      Shadow(
                        color: const Color(0xFF7CFF9A).withValues(alpha: 0.25),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                if (parts.unit != null) ...[
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    parts.unit!,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: unitSize,
                      letterSpacing: 1.6,
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
    final bandY = size.height * (0.35 + 0.08 * math.sin(size.width));
    canvas.drawRect(
      Rect.fromLTWH(0, bandY, size.width, 10),
      Paint()..color = const Color(0xFF7CFF9A).withValues(alpha: 0.04),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
