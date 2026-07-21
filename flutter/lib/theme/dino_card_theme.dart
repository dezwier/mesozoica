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
  static const double factPanelBorderRadius = 10;

  /// Matches [frontPlaceholderAsset] (1086×1448) so the cover image is not cropped.
  static const double cardAspectRatio = 1086 / 1448;

  /// Portrait 3:4 thumbnails for site and dinosaur cards on fossil card backs.
  static const double fossilThumbAspectRatio = 3 / 4;

  static const String frontPlaceholderAsset =
      'assets/images/cards/dinosaur_card_front_placeholder.png';

  static const String fossilPlaceholderAsset =
      'assets/images/cards/fossil_card_front_placeholder.png';

  static const String sitePlaceholderAsset =
      'assets/images/cards/site_card_front_placeholder.png';

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

  /// Title on the card front image — light tone with shadow for readability.
  TextStyle frontOverlayTitleStyle({double fontSize = 28}) {
    return TextStyle(
      fontFamily: titleFontFamily,
      color: const Color(0xFFF8F4EE),
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      height: 1.1,
      shadows: const [
        Shadow(
          color: Color(0x8C000000),
          blurRadius: 8,
          offset: Offset(0, 1),
        ),
        Shadow(
          color: Color(0x59000000),
          blurRadius: 14,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  /// Compact labels on rotate-mode map circles (white text, strong shadow).
  TextStyle mapMarkerLabelStyle({required double fontSize}) {
    return TextStyle(
      fontFamily: titleFontFamily,
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      height: 1.1,
      shadows: const [
        Shadow(
          color: Color(0xCC000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
        Shadow(
          color: Color(0x99000000),
          blurRadius: 3,
          offset: Offset(0, 0),
        ),
      ],
    );
  }

  /// Subtitle paired with [frontOverlayTitleStyle] on the card image.
  TextStyle frontOverlaySubtitleStyle({double fontSize = 10}) {
    return TextStyle(
      color: const Color(0xE6F0E8DF),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      height: 1.2,
      shadows: const [
        Shadow(
          color: Color(0x73000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  /// Description text on the card front image.
  TextStyle frontOverlayBodyStyle({double fontSize = 13}) {
    return TextStyle(
      color: const Color.fromARGB(230, 255, 255, 255),
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.4,
      shadows: const [
        Shadow(
          color: Color(0x73000000),
          blurRadius: 6,
          offset: Offset(0, 1),
        ),
        Shadow(
          color: Color(0x40000000),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    );
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

  /// Stat / section panels — matches profile cards (radius 10, elevation 1,
  /// surfaceContainerHighest wash on [ColorScheme.surface]).
  BoxDecoration factPanelDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: Color.alphaBlend(
        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        scheme.surface,
      ),
      borderRadius: BorderRadius.circular(factPanelBorderRadius),
      boxShadow: kElevationToShadow[1],
    );
  }

  /// Darkening wash over the blurred back image (darker at top for light titles).
  LinearGradient backFaceImageOverlayGradient() {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xA64C4643),
        Color(0x447E7671),
        Color(0x33B4ADA7),
      ],
      stops: [0.0, 0.28, 1.0],
    );
  }

  /// Soft metallic highlight washed across the back face.
  LinearGradient backFaceSheenGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: isLight ? 0.03 : 0.02),
        Colors.transparent,
        Colors.black.withValues(alpha: isLight ? 0.025 : 0.05),
      ],
      stops: const [0.0, 0.45, 1.0],
    );
  }

  /// Bottom overlay on the card front illustration.
  LinearGradient frontOverlayGradient() {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.transparent,
        Color(0x66000000),
        Color.fromARGB(145, 0, 0, 0),
        Color.fromARGB(173, 0, 0, 0),
        Color.fromARGB(196, 0, 0, 0),
        Color.fromARGB(197, 0, 0, 0),
      ],
      stops: [0.0, 0.42, 0.55, 0.68, 0.80, 0.92, 1.0],
    );
  }
}
