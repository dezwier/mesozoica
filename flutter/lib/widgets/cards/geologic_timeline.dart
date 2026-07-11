import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Fixed deep-time scale from 250 Ma (top) to 66 Ma (bottom).
class GeologicTimeline extends StatelessWidget {
  const GeologicTimeline({
    super.key,
    this.birth,
    this.death,
    this.minMa = 250,
    this.maxMa = 66,
  });

  final double? birth;
  final double? death;
  final double minMa;
  final double maxMa;

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

    final labelColor = DinoCardTheme.labelColor(context);
    final accentColor = DinoCardTheme.accentColor(context);
    final lineColor = DinoCardTheme.lineColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'TIME',
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 48,
          height: 140,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.35),
                        lineColor,
                        accentColor,
                      ],
                    ),
                  ),
                ),
              ),
              if (startPos != null && endPos != null)
                Positioned(
                  top: (1 - startPos.clamp(0.0, 1.0)) * 140,
                  bottom: endPos.clamp(0.0, 1.0) * 140,
                  right: 18,
                  child: Container(
                    width: 10,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                )
              else if (startPos != null)
                Positioned(
                  top: (1 - startPos.clamp(0.0, 1.0)) * 140 - 4,
                  right: 16,
                  child: _TimelineDot(color: accentColor),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: _TimelineLabel('${minMa.round()} Ma', color: labelColor),
              ),
              Positioned(
                top: 52,
                right: 0,
                child: _TimelineLabel('201 Ma', color: labelColor),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: _TimelineLabel('${maxMa.round()} Ma', color: labelColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 9,
      ),
    );
  }
}
