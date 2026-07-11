import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

class CladogramStrip extends StatelessWidget {
  const CladogramStrip({
    super.key,
    required this.lineage,
  });

  final List<String> lineage;

  @override
  Widget build(BuildContext context) {
    if (lineage.isEmpty) {
      return const Text(
        '—',
        style: TextStyle(color: DinoCardTheme.subtitleMuted, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CLADOGRAM',
          style: TextStyle(
            color: DinoCardTheme.labelBronze,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(lineage.length, (index) {
          final isLast = index == lineage.length - 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLast
                            ? DinoCardTheme.timelineAccent
                            : DinoCardTheme.cladogramLine,
                        border: Border.all(
                          color: DinoCardTheme.borderGold,
                          width: 1,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 18,
                        color: DinoCardTheme.cladogramLine.withValues(alpha: 0.7),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
                  child: Text(
                    lineage[index].toUpperCase(),
                    style: TextStyle(
                      color: isLast
                          ? DinoCardTheme.titleWhite
                          : DinoCardTheme.subtitleMuted,
                      fontSize: isLast ? 12 : 10,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
