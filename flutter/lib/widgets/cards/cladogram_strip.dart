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
      return Text(
        '—',
        style: TextStyle(
          color: DinoCardTheme.labelColor(context),
          fontSize: 12,
        ),
      );
    }

    final labelColor = DinoCardTheme.labelColor(context);
    final titleColor = DinoCardTheme.titleColor(context);
    final accentColor = DinoCardTheme.accentColor(context);
    final lineColor = DinoCardTheme.lineColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CLADOGRAM',
          style: TextStyle(
            color: labelColor,
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
                        color: isLast ? accentColor : lineColor,
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 18,
                        color: lineColor,
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
                      color: isLast ? titleColor : labelColor,
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
