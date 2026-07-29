import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/theme/mesozoica_theme.dart';
import 'package:mesozoica/widgets/map/period_marker_color.dart';

void main() {
  test('periodMarkerColor uses light-theme colors in dark mode', () {
    final lightPrimary = MesozoicaTheme.light.colorScheme.primary;
    final darkPrimary = MesozoicaTheme.dark.colorScheme.primary;

    expect(periodMarkerColor('cretaceous'), lightPrimary);
    expect(periodMarkerColor('cretaceous'), isNot(darkPrimary));
    expect(periodMarkerColor('jurassic'), const Color.fromARGB(255, 90, 154, 108));
    expect(periodMarkerColor('triassic'), const Color.fromARGB(255, 221, 133, 0));
    expect(periodMarkerColor('Cretaceous'), lightPrimary);
    expect(periodMarkerColor(null), lightPrimary);
    expect(mapMarkerPrimaryColor(), lightPrimary);
  });
}
