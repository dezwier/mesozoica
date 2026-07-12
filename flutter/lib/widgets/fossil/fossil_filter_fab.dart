import 'package:flutter/material.dart';

import '../dino/dinosaur_filter_fab.dart';

class FossilFilterFab extends StatelessWidget {
  const FossilFilterFab({
    super.key,
    required this.onPressed,
    this.hasActiveFilters = false,
    this.heroTag = 'fossil_filter_fab',
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
