import 'package:flutter/material.dart';

import '../dino/dinosaur_filter_fab.dart';

class FossilFilterFab extends StatelessWidget {
  const FossilFilterFab({
    super.key,
    required this.onPressed,
    this.hasActiveFilters = false,
  });

  final VoidCallback onPressed;
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    return DinosaurFilterFab(
      heroTag: 'fossil_filter_fab',
      onPressed: onPressed,
      hasActiveFilters: hasActiveFilters,
    );
  }
}
