import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Card chrome aligned with archipelago dictionary cards — surface fill, soft shadow, no border.
class DinoCardTheme {
  DinoCardTheme._();

  static const double borderRadius = 16;

  static List<BoxShadow> boxShadow({double flipAngleRadians = 0}) {
    final depth =
        0.20 + (0.05 * math.sin(flipAngleRadians.abs()).clamp(0.0, 1.0));
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: depth * 0.45),
        blurRadius: 34,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: depth),
        blurRadius: 16,
        spreadRadius: 0,
      ),
    ];
  }

  static BoxDecoration chromeDecoration(
    BuildContext context, {
    double flipAngleRadians = 0,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: boxShadow(flipAngleRadians: flipAngleRadians),
    );
  }

  static Color labelColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color titleColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color accentColor(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color lineColor(BuildContext context) =>
      Theme.of(context).colorScheme.outline.withValues(alpha: 0.55);

  static Color placeholderSurface(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
}
