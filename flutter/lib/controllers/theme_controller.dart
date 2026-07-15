import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/mesozoica_theme.dart';

class ThemeController extends ChangeNotifier {
  static const _themeModeKey = 'theme_mode';

  ThemeMode _themeMode = MesozoicaTheme.defaultThemeMode;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final key = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString(_themeModeKey, key);
  }
}
