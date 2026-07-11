import 'package:flutter/material.dart';

class DinosaurFilterFab extends StatelessWidget {
  const DinosaurFilterFab({
    super.key,
    required this.onPressed,
    this.hasActiveFilters = false,
    this.heroTag = 'dino_filter_fab',
  });

  final VoidCallback onPressed;
  final bool hasActiveFilters;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onPressed,
          tooltip: 'Filter',
          backgroundColor: colorScheme.surfaceContainerHighest,
          foregroundColor: colorScheme.onSurface,
          child: const Icon(Icons.filter_list),
        ),
        if (hasActiveFilters)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
