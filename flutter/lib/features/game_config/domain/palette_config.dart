// Typed parsers for period and rock-type color YAML documents.

import 'config_parsing.dart';

(int, int, int) _requireRgb(dynamic value, String key) {
  if (value is String) {
    final raw = value.trim().replaceFirst('#', '');
    if (raw.length == 6) {
      final r = int.tryParse(raw.substring(0, 2), radix: 16);
      final g = int.tryParse(raw.substring(2, 4), radix: 16);
      final b = int.tryParse(raw.substring(4, 6), radix: 16);
      if (r != null && g != null && b != null) return (r, g, b);
    }
  }
  if (value is List && value.length == 3) {
    final r = value[0] is num ? (value[0] as num).round() : null;
    final g = value[1] is num ? (value[1] as num).round() : null;
    final b = value[2] is num ? (value[2] as num).round() : null;
    if (r != null &&
        g != null &&
        b != null &&
        r >= 0 &&
        r <= 255 &&
        g >= 0 &&
        g <= 255 &&
        b >= 0 &&
        b <= 255) {
      return (r, g, b);
    }
  }
  throw FormatException('period_colors.yaml: $key must be #RRGGBB');
}

class PeriodRgbColors {
  const PeriodRgbColors({
    required this.cretaceous,
    required this.jurassic,
    required this.triassic,
  });

  final (int, int, int) cretaceous;
  final (int, int, int) jurassic;
  final (int, int, int) triassic;

  factory PeriodRgbColors.fromYaml(Map<String, dynamic> yaml) {
    return PeriodRgbColors(
      cretaceous: _requireRgb(yaml['cretaceous'], 'cretaceous'),
      jurassic: _requireRgb(yaml['jurassic'], 'jurassic'),
      triassic: _requireRgb(yaml['triassic'], 'triassic'),
    );
  }

  (int, int, int) forPeriod(String period) {
    switch (period.toLowerCase()) {
      case 'jurassic':
        return jurassic;
      case 'triassic':
        return triassic;
      case 'cretaceous':
      default:
        return cretaceous;
    }
  }
}

class PeriodColorsConfig {
  const PeriodColorsConfig({
    required this.siteMarkers,
    required this.orbitSurvey,
  });

  final PeriodRgbColors siteMarkers;
  final PeriodRgbColors orbitSurvey;

  factory PeriodColorsConfig.fromYaml(Map<String, dynamic> yaml) {
    return PeriodColorsConfig(
      siteMarkers: PeriodRgbColors.fromYaml(configAsMap(yaml['site_markers'])),
      orbitSurvey: PeriodRgbColors.fromYaml(configAsMap(yaml['orbit_survey'])),
    );
  }
}

class RockTypeColorsConfig {
  const RockTypeColorsConfig({required this.formationMap});

  final Map<String, (int, int, int)> formationMap;

  (int, int, int) forRockType(String? rockType) {
    final key = (rockType ?? '').trim().toLowerCase();
    if (key.isNotEmpty && formationMap.containsKey(key)) {
      return formationMap[key]!;
    }
    return formationMap['other'] ?? (0x88, 0x88, 0x88);
  }

  factory RockTypeColorsConfig.fromYaml(Map<String, dynamic> yaml) {
    final raw = configAsMap(yaml['formation_map']);
    final colors = <String, (int, int, int)>{};
    for (final entry in raw.entries) {
      colors[entry.key.toString().trim().toLowerCase()] = _requireRgb(
        entry.value,
        entry.key.toString(),
      );
    }
    return RockTypeColorsConfig(formationMap: colors);
  }
}
