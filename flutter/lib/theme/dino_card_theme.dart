import 'package:flutter/material.dart';

/// Museum-style card chrome separate from app theme.
class DinoCardTheme {
  DinoCardTheme._();

  static const Color background = Color(0xFF121110);
  static const Color backgroundElevated = Color(0xFF1C1B1F);
  static const Color borderBronze = Color(0xFF8B6914);
  static const Color borderGold = Color(0xFFCD7F32);
  static const Color labelBronze = Color(0xFFB8860B);
  static const Color titleWhite = Color(0xFFF5F5F5);
  static const Color subtitleMuted = Color(0xFFBCAAA4);
  static const Color timelineAccent = Color(0xFFFF8C42);
  static const Color cladogramLine = Color(0xFFCD7F32);

  static const double borderRadius = 14;
  static const double borderWidth = 1.5;

  static BoxDecoration get chromeDecoration => BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderGold, width: borderWidth),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      );
}
