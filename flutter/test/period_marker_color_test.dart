import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/theme/mesozoica_theme.dart';
import 'package:mesozoica/widgets/map/period_marker_color.dart';

void main() {
  test('periodMarkerColor maps periods to theme browns lightest to darkest', () {
    final scheme = MesozoicaTheme.light.colorScheme;

    expect(periodMarkerColor('cretaceous', scheme), scheme.primary);
    expect(periodMarkerColor('jurassic', scheme), scheme.secondary);
    expect(periodMarkerColor('triassic', scheme), scheme.tertiary);
    expect(periodMarkerColor('Cretaceous', scheme), scheme.primary);
    expect(periodMarkerColor(null, scheme), scheme.primary);
  });
}
