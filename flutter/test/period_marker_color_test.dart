import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/widgets/map/period_marker_color.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  setUp(() async {
    GameConfig.debugReset();
    await loadGameConfigForTest();
  });

  tearDown(GameConfig.debugReset);

  test('periodMarkerColor reads site_markers from period_colors.yaml', () {
    final markers = GameConfig.instance.periodColors.siteMarkers;
    Color rgb((int, int, int) c) => Color.fromARGB(255, c.$1, c.$2, c.$3);

    expect(periodMarkerColor('cretaceous'), rgb(markers.cretaceous));
    expect(periodMarkerColor('jurassic'), rgb(markers.jurassic));
    expect(periodMarkerColor('triassic'), rgb(markers.triassic));
    expect(periodMarkerColor('Cretaceous'), rgb(markers.cretaceous));
    // Unidentified sites use a neutral gray, not the Cretaceous pin color.
    expect(periodMarkerColor(null), const Color(0xFF8A867C));
    expect(periodMarkerColor(''), const Color(0xFF8A867C));
    expect(periodMarkerColor('unknown'), const Color(0xFF8A867C));
    expect(mapMarkerPrimaryColor(), rgb(markers.cretaceous));
  });
}
