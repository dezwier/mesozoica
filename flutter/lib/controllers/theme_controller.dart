import 'package:flutter/material.dart';

import '../theme/mesozoica_theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = MesozoicaTheme.defaultThemeMode;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  void toggle() {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
}
