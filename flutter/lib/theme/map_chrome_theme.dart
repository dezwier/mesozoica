import 'package:flutter/material.dart';

/// Shared colors for floating map chrome (HUD, toggle, pins, FABs, bottom bar).
abstract final class MapChromeTheme {
  static const Color gold = Color(0xFFC5944E);
  static const Color goldBright = Color(0xFFD4AF37);
  static const Color cream = Color(0xFFF5F0E6);
  static const Color creamCard = Color(0xFFFAF7F2);
  static const Color darkGlass = Color(0x8C000000); // ~0.55
  static const Color darkGlassSoft = Color(0x73000000); // ~0.45
  static const Color brownText = Color(0xFF4A3F38);
  static const Color bluePuck = Color(0xFF2F80ED);
  static const Color bluePuckGlow = Color(0x662F80ED);
  static const Color warmFab = Color(0xFF6B5348);
  static const Color labelMuted = Color(0xFF6D5C50);
}
