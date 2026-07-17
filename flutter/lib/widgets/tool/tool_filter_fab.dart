import 'package:flutter/material.dart';

import '../dino/dinosaur_filter_fab.dart';

class ToolFilterFab extends StatelessWidget {
  const ToolFilterFab({
    super.key,
    required this.onPressed,
    this.hasActiveFilters = false,
    this.heroTag = 'tool_filter_fab',
  });

  final VoidCallback onPressed;
  final bool hasActiveFilters;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return DinosaurFilterFab(
      heroTag: heroTag,
      onPressed: onPressed,
      hasActiveFilters: hasActiveFilters,
    );
  }
}
