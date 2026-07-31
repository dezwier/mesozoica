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

  // --- Vintage explorer chrome ---

  /// Shared leather brown for the bottom bar.
  static const Color leather = Color(0xFF3A322C);
  static const Color leatherMid = Color(0xFF463C34);
  static const Color leatherHighlight = Color(0xFF554840);

  /// Slightly lighter leather for FABs and Archive/Field toggle.
  static const Color leatherSoft = Color(0xFF4A4038);
  static const Color leatherSoftMid = Color(0xFF5A4E44);
  static const Color leatherSoftHighlight = Color(0xFF6A5C50);

  /// Soft warm brass / bronze — muted, not cold or highly saturated.
  static const Color brassLight = Color(0xFFC2B29A);
  static const Color brassMid = Color(0xFF9A8A74);
  static const Color brassDark = Color(0xFF6E6050);
  static const Color brassRim = Color(0xFFA89880);

  /// Shared muted border for FABs / toggle / notification.
  static Color get chromeBorder => brassRim.withValues(alpha: 0.55);
  static const double chromeBorderWidth = 1.0;

  /// Dial faces use the lighter leather (FABs / notification).
  static const Color dialFace = leatherSoftMid;
  static const Color dialFaceWarm = leatherSoftHighlight;
  static const Color dialFaceDeep = leatherSoft;
  static const Color dialFaceGrey = Color(0xFF5A544C);

  /// Near-flat parchment (marker labels / selected toggle).
  static const Color parchment = Color(0xFFF6F1E8);
  static const Color parchmentEdge = Color(0xFFD0C6B4);
  static const Color parchmentShadow = Color(0xFFF0EAE0);

  /// Soft sandstone wash over the basemap (~15%).
  static const Color mapSandstoneWash = Color.fromARGB(61, 210, 180, 140);

  /// Muted gold for chrome labels (nav, inactive toggle).
  static const Color mutedGold = Color(0xFFC4B8A4);
  static const Color hudGold = Color(0xFFD4C8B4);

  static const String serifFont = 'tt_ramilas';
}
