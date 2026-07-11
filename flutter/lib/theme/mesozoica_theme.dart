import 'package:flutter/material.dart';

/// Brown/sandstone Material 3 theme ported from mesosoica.
class MesozoicaTheme {
  MesozoicaTheme._();

  static const ThemeMode defaultThemeMode = ThemeMode.dark;

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF8D6E63),
          onPrimary: Colors.white,
          secondary: Color(0xFFBCAAA4),
          onSecondary: Color(0xFF3E2723),
          tertiary: Color(0xFFD7CCC8),
          onTertiary: Color(0xFF3E2723),
          surface: Color(0xFFF5F5F5),
          onSurface: Color(0xFF3E2723),
          surfaceContainerHighest: Color(0xFFE8E0DB),
          onSurfaceVariant: Color(0xFF5D4037),
          outline: Color(0xFF8D6E63),
          outlineVariant: Color(0xFFBCAAA4),
          error: Color(0xFFD32F2F),
          onError: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(height: 60),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA79E9B),
          onPrimary: Color(0xFF3E2723),
          secondary: Color(0xFF8D6E63),
          onSecondary: Colors.white,
          tertiary: Color(0xFFD7CCC8),
          onTertiary: Color(0xFF3E2723),
          surface: Color(0xFF1C1B1F),
          onSurface: Color(0xFFD7CCC8),
          surfaceContainerHighest: Color(0xFF2D2A2E),
          onSurfaceVariant: Color(0xFFBCAAA4),
          outline: Color(0xFF8D6E63),
          outlineVariant: Color(0xFF5D4037),
          error: Color(0xFFF28B82),
          onError: Color(0xFF601410),
        ),
        navigationBarTheme: const NavigationBarThemeData(height: 60),
      );
}
