import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Museum card palette — dark and light variants aligned with [MesozoicaTheme].
class DinoCardTheme {
  const DinoCardTheme._({
    required this.isLight,
    required this.cardBackground,
    required this.cardAccent,
    required this.cardTextPrimary,
    required this.cardTextSecondary,
    required this.cardTextMuted,
    required this.shadowColor,
    required this.frontTitleColor,
  });

  static const double borderRadius = 16;

  /// Matches [frontPlaceholderAsset] (493×677) so the cover image is not cropped.
  static const double cardAspectRatio = 493 / 677;

  static const String frontPlaceholderAsset =
      'assets/images/cards/dinosaur_card_front_placeholder.png';

  static const String fossilPlaceholderAsset =
      'assets/images/cards/fossil_card_front_placeholder.png';

  static const String titleFontFamily = 'tt_ramilas';

  static const DinoCardTheme dark = DinoCardTheme._(
    isLight: false,
    cardBackground: Color(0xFF1A1A1A),
    cardAccent: Color(0xFFC5944E),
    cardTextPrimary: Colors.white,
    cardTextSecondary: Color(0xFFC5944E),
    cardTextMuted: Color(0x73FFFFFF),
    shadowColor: Colors.black,
    frontTitleColor: Color(0xFFA08B7A),
  );

  static const DinoCardTheme light = DinoCardTheme._(
    isLight: true,
    cardBackground: Color(0xFFFAF7F2),
    cardAccent: Color(0xFFC5944E),
    cardTextPrimary: Color(0xFF3E2723),
    cardTextSecondary: Color(0xFF5D4037),
    cardTextMuted: Color(0xFF4E342E),
    shadowColor: Color(0xFF3E2723),
    frontTitleColor: Color.fromARGB(255, 48, 40, 36),
  );

  final bool isLight;
  final Color cardBackground;
  final Color cardAccent;
  final Color cardTextPrimary;
  final Color cardTextSecondary;
  final Color cardTextMuted;
  final Color shadowColor;
  final Color frontTitleColor;

  static DinoCardTheme of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  List<BoxShadow> boxShadow({double flipAngleRadians = 0}) {
    final depth =
        0.20 + (0.05 * math.sin(flipAngleRadians.abs()).clamp(0.0, 1.0));
    return [
      BoxShadow(
        color: shadowColor.withValues(alpha: depth * 0.45),
        blurRadius: 34,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: shadowColor.withValues(alpha: depth),
        blurRadius: 16,
        spreadRadius: 0,
      ),
    ];
  }

  BoxDecoration chromeDecoration({double flipAngleRadians = 0}) {
    return BoxDecoration(
      color: cardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: boxShadow(flipAngleRadians: flipAngleRadians),
    );
  }

  BoxDecoration cardFaceDecoration() {
    return BoxDecoration(color: cardBackground);
  }

  TextStyle titleStyle({double fontSize = 18, Color? color}) {
    return TextStyle(
      fontFamily: titleFontFamily,
      color: color ?? cardTextPrimary,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      height: 1.1,
    );
  }

  TextStyle frontTitleStyle({double fontSize = 28}) {
    return titleStyle(fontSize: fontSize, color: frontTitleColor);
  }

  TextStyle subtitleStyle({double fontSize = 11}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      height: 1.2,
    );
  }

  TextStyle statLabelStyle({double fontSize = 9}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      height: 1.1,
    );
  }

  TextStyle statValueStyle({double fontSize = 12}) {
    return TextStyle(
      color: cardTextPrimary,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  TextStyle bodyStyle({double fontSize = 11}) {
    return TextStyle(
      color: cardTextPrimary.withValues(alpha: 0.92),
      fontSize: fontSize,
      height: 1.35,
    );
  }

  TextStyle sectionLabelStyle({double fontSize = 9}) {
    return TextStyle(
      color: cardTextSecondary,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );
  }

  TextStyle rankLabelStyle({double fontSize = 8}) {
    return TextStyle(
      color: isLight
          ? cardTextSecondary.withValues(alpha: 0.55)
          : cardTextMuted,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      height: 1.1,
    );
  }

  /// Non-highlighted cladogram taxon names.
  Color cladogramNodeColor({required bool isLast}) {
    if (isLast) return cardTextPrimary;
    return isLight ? cardTextSecondary : cardAccent.withValues(alpha: 0.85);
  }

  /// Small timeline annotations (e.g. "252 Ma").
  Color timelineAnnotationColor() {
    return isLight ? cardTextMuted : cardTextPrimary.withValues(alpha: 0.5);
  }

  /// Period names on the geologic timeline.
  Color periodLabelColor() {
    return isLight ? cardTextSecondary : cardAccent.withValues(alpha: 0.9);
  }

  /// Bottom overlay on the card front illustration.
  LinearGradient frontOverlayGradient() {
    if (isLight) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          cardBackground.withValues(alpha: 0.12),
          cardBackground.withValues(alpha: 0.30),
          cardBackground.withValues(alpha: 0.55),
          cardBackground.withValues(alpha: 0.76),
          cardBackground.withValues(alpha: 0.92),
          cardBackground,
        ],
        stops: const [0.0, 0.12, 0.28, 0.40, 0.55, 0.82, 1.0],
      );
    }

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        cardBackground.withValues(alpha: 0.55),
        cardBackground.withValues(alpha: 0.85),
        cardBackground,
      ],
      stops: const [0.0, 0.18, 0.42, 1.0],
    );
  }
}
