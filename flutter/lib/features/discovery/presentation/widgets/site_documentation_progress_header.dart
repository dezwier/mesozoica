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
  });

  final double progress;
  final String message;
  final bool active;
  final bool complete;
  final DinoCardTheme cardTheme;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    final accent = cardTheme.cardAccent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 30,
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
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    complete
                        ? Icons.check_circle_rounded
                        : active
                        ? Icons.auto_awesome_rounded
                        : Icons.location_on_outlined,
                    size: 15,
                    color: cardTheme.cardTextPrimary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cardTheme
                          .sectionLabelStyle(fontSize: 11)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: cardTheme
                        .sectionLabelStyle(fontSize: 11)
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
