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

  static const _periods = [
    _PeriodMarker('Triassic', 250),
    _PeriodMarker('Jurassic', 201),
    _PeriodMarker('Cretaceous', 66),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('TIME', style: DinoCardTheme.sectionLabelStyle(fontSize: 10)),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final timelineHeight = constraints.maxHeight;

              return SizedBox(
                width: constraints.maxWidth,
                height: timelineHeight,
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
                              DinoCardTheme.cardAccent.withValues(alpha: 0.35),
                              DinoCardTheme.cardAccent,
                              DinoCardTheme.cardAccent.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (startPos != null && endPos != null)
                      Positioned(
                        left: 28,
                        top: (1 - startPos.clamp(0.0, 1.0)) * timelineHeight,
                        bottom: endPos.clamp(0.0, 1.0) * timelineHeight,
                        child: Container(
                          width: 11,
                          decoration: BoxDecoration(
                            color: DinoCardTheme.cardAccent.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color:
                                  DinoCardTheme.cardAccent.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      )
                    else if (startPos != null)
                      Positioned(
                        left: 27,
                        top: (1 - startPos.clamp(0.0, 1.0)) * timelineHeight - 5,
                        child: _TimelineDot(color: DinoCardTheme.cardAccent),
                      ),
                    for (final period in _periods)
                      Positioned(
                        top: (1 -
                                    _positionForMa(period.ma.toDouble())!
                                        .clamp(0.0, 1.0)) *
                                timelineHeight -
                            10,
                        left: 0,
                        right: 0,
                        child: _PeriodLabel(
                          name: period.name,
                          ma: period.ma,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PeriodMarker {
  const _PeriodMarker(this.name, this.ma);

  final String name;
  final int ma;
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: DinoCardTheme.cardTextPrimary, width: 1),
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.name, required this.ma});

  final String name;
  final int ma;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: DinoCardTheme.cardAccent.withValues(alpha: 0.9),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$ma Ma',
                style: TextStyle(
                  color: DinoCardTheme.cardTextPrimary.withValues(alpha: 0.75),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DinoCardTheme.cardAccent.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
