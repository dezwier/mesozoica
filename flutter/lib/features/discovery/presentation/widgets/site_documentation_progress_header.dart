import 'package:flutter/material.dart';

import '../../../../theme/dino_card_theme.dart';

/// Live aggregate documentation status shown above site dimensions.
class SiteDocumentationProgressHeader extends StatelessWidget {
  const SiteDocumentationProgressHeader({
    super.key,
    required this.progress,
    required this.message,
    required this.active,
    required this.complete,
    required this.cardTheme,
    this.height = 30.0,
  });

  final double progress;
  final String message;
  final bool active;
  final bool complete;
  final DinoCardTheme cardTheme;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final accent = cardTheme.cardAccent;
    final double fontSize = height < 26 ? 9.5 : 11;
    final double iconSize = height < 26 ? 12 : 15;

    return ClipRRect(
      borderRadius: BorderRadius.circular(height * 0.3),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: cardTheme.cardTextMuted.withValues(alpha: 0.12)),
            TweenAnimationBuilder<double>(
              tween: Tween(end: value),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: animated,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: active ? 0.78 : 0.52),
                        accent.withValues(alpha: complete ? 0.95 : 0.68),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: height < 26 ? 8 : 10),
              child: Row(
                children: [
                  Icon(
                    complete
                        ? Icons.check_circle_rounded
                        : active
                        ? Icons.auto_awesome_rounded
                        : Icons.location_on_outlined,
                    size: iconSize,
                    color: cardTheme.cardTextPrimary,
                  ),
                  SizedBox(width: height < 26 ? 4 : 6),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cardTheme
                          .sectionLabelStyle(fontSize: fontSize)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: cardTheme
                        .sectionLabelStyle(fontSize: fontSize)
                        .copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
