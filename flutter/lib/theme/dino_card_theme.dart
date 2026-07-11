import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dark museum card palette aligned with the reference mockup.
class DinoCardTheme {
  DinoCardTheme._();

  static const double borderRadius = 16;

  static const Color cardBackground = Color(0xFF1A1A1A);
  static const Color cardAccent = Color(0xFFC5944E);
  static const Color cardTextPrimary = Colors.white;
  static const Color cardTextSecondary = Color(0xFFC5944E);

  static const String frontPlaceholderAsset =
      'assets/images/cards/dinosaur_card_front_placeholder.png';

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
    return BoxDecoration(
      color: cardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: boxShadow(flipAngleRadians: flipAngleRadians),
    );
  }

  static BoxDecoration cardFaceDecoration() {
    return const BoxDecoration(
      color: cardBackground,
    );
  }

  static TextStyle titleStyle({double fontSize = 18}) {
    return TextStyle(
      color: cardTextPrimary,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      height: 1.1,
    );
  }

  static TextStyle subtitleStyle({double fontSize = 11}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      height: 1.2,
    );
  }

  static TextStyle statLabelStyle({double fontSize = 9}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      height: 1.1,
    );
  }

  static TextStyle statValueStyle({double fontSize = 12}) {
    return TextStyle(
      color: cardTextPrimary,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  static TextStyle bodyStyle({double fontSize = 11}) {
    return TextStyle(
      color: cardTextPrimary.withValues(alpha: 0.92),
      fontSize: fontSize,
      height: 1.35,
    );
  }

  static TextStyle sectionLabelStyle({double fontSize = 9}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );
  }

  // Legacy helpers kept for any remaining theme-aware call sites.
  static Color labelColor(BuildContext context) => cardTextSecondary;

  static Color titleColor(BuildContext context) => cardTextPrimary;

  static Color accentColor(BuildContext context) => cardAccent;

  static Color lineColor(BuildContext context) =>
      cardAccent.withValues(alpha: 0.55);

  static Color placeholderSurface(BuildContext context) => cardBackground;
}
