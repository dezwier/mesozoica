import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/theme/mesozoica_theme.dart';
import 'package:mesozoica/widgets/map/period_marker_color.dart';

void main() {
  test('periodMarkerColor maps periods to theme colors', () {
    final scheme = MesozoicaTheme.light.colorScheme;

    expect(periodMarkerColor('cretaceous', scheme), scheme.primary);
    expect(
      periodMarkerColor('jurassic', scheme),
      const Color.fromARGB(255, 195, 195, 195),
    );
    expect(
      periodMarkerColor('triassic', scheme),
      const Color.fromARGB(255, 221, 133, 0),
    );
    expect(periodMarkerColor('Cretaceous', scheme), scheme.primary);
    expect(periodMarkerColor(null, scheme), scheme.primary);
  });
}
