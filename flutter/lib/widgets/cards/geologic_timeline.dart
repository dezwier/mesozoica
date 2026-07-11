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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'TIME',
          style: TextStyle(
            color: DinoCardTheme.labelBronze,
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
                        DinoCardTheme.cladogramLine.withValues(alpha: 0.4),
                        DinoCardTheme.cladogramLine,
                        DinoCardTheme.timelineAccent,
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
                      color: DinoCardTheme.timelineAccent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: DinoCardTheme.timelineAccent),
                    ),
                  ),
                )
              else if (startPos != null)
                Positioned(
                  top: (1 - startPos.clamp(0.0, 1.0)) * 140 - 4,
                  right: 16,
                  child: _TimelineDot(),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: _TimelineLabel('${minMa.round()} Ma'),
              ),
              Positioned(
                top: 52,
                right: 0,
                child: _TimelineLabel('201 Ma'),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: _TimelineLabel('${maxMa.round()} Ma'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DinoCardTheme.timelineAccent,
        boxShadow: [
          BoxShadow(
            color: DinoCardTheme.timelineAccent.withValues(alpha: 0.6),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _TimelineLabel extends StatelessWidget {
  const _TimelineLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: DinoCardTheme.subtitleMuted,
        fontSize: 9,
      ),
    );
  }
}
