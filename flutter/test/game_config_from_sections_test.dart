import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';

/// Minimal set of sections that the parsers treat as mandatory
/// (`period_colors` requires valid #RRGGBB triples).
Map<String, dynamic> _mandatorySections() => <String, dynamic>{
      'period_colors': {
        'site_markers': {
          'cretaceous': '#8d6e63',
          'jurassic': '#6d9f71',
          'triassic': '#b0714a',
        },
        'orbit_survey': {
          'cretaceous': '#8d6e63',
          'jurassic': '#6d9f71',
          'triassic': '#b0714a',
        },
      },
    };

void main() {
  tearDown(GameConfig.debugReset);

  test('fromSections parses values from decoded JSON sections', () {
    final config = GameConfig.fromSections(<String, dynamic>{
      ..._mandatorySections(),
      'site_generation': {
        'lazy': {'cell_size_m': 750.0},
      },
      'site_discovery': {
        'skill_id': 'site_discovery',
        'main_params': {
          'visibility_distance_m': 25.0,
          'discovery_chance': 0.42,
          'max_discovery_speed_kmh': 12.0,
        },
      },
      'leveling': {
        'skills': [
          {'id': 'site_discovery', 'name': 'Site Discovery'},
        ],
        'career_titles': ['Curious Wanderer'],
      },
    });

    expect(config.siteDiscovery.discoveryChance, 0.42);
    expect(config.siteDiscovery.visibilityDistanceM, 25.0);
    expect(config.siteDiscovery.maxDiscoverySpeedKmh, 12.0);
    expect(config.siteGeneration.cellSizeM, 750.0);
    expect(config.leveling.skills.first.id, 'site_discovery');
    // The singleton is installed, so all existing call sites keep working.
    expect(GameConfig.instance.siteDiscovery.discoveryChance, 0.42);
    expect(
      config.periodColors.siteMarkers.forPeriod('jurassic'),
      (0x6d, 0x9f, 0x71),
    );
  });

  test('fromSections applies parser defaults for omitted optional sections', () {
    final config = GameConfig.fromSections(_mandatorySections());

    // Optional/skill sections fall back to parser defaults, keeping the app
    // functional on a lean payload.
    expect(config.siteDiscovery.discoveryChance, 0.1);
    expect(config.siteGeneration.cellSizeM, 500.0);
    expect(config.leveling.skills, isEmpty);
  });
}
