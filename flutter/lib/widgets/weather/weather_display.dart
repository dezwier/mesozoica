import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared labels, icons, and day/night asset paths for weather HUD + detail sheet.
///
/// Weather [type] is time-agnostic (`clear`, not sunny). Day vs night is chosen
/// from [weatherTime] when resolving illustrated assets.
abstract final class WeatherDisplay {
  WeatherDisplay._();

  static const _assetDir = 'assets/images/weather';

  static const weatherTypes = <String>[
    'clear',
    'cloudy',
    'overcast',
    'fog',
    'drizzle',
    'rain',
    'snow',
    'thunderstorm',
    'hail',
  ];

  /// Solar periods in preferred chrome order (current value is pinned first in UI).
  static const weatherTimes = <String>[
    'day',
    'night',
    'golden_hour',
    'dusk',
    'dawn',
  ];

  /// [current] first, then remaining [all] keys in their given order.
  static List<String> optionsWithCurrentFirst(
    List<String> all,
    String current,
  ) {
    final normalized = current == 'sunny' ? 'clear' : current;
    final rest = <String>[
      for (final key in all)
        if (key != normalized) key,
    ];
    if (all.contains(normalized)) return [normalized, ...rest];
    return List<String>.from(all);
  }

  /// Night-side art for dusk + night; day-side art for dawn / day / golden hour.
  static bool usesNightArt(String weatherTime) {
    return weatherTime == 'night' || weatherTime == 'dusk';
  }

  static String artPeriod(String weatherTime) =>
      usesNightArt(weatherTime) ? 'night' : 'day';

  /// Illustrated asset for [type] + [weatherTime], or null if unknown.
  static String? assetPath(String type, {required String weatherTime}) {
    final normalized = type == 'sunny' ? 'clear' : type;
    if (!weatherTypes.contains(normalized)) return null;
    return '$_assetDir/weather_${normalized}_${artPeriod(weatherTime)}.png';
  }

  static IconData weatherIcon(String type, {String? weatherTime}) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'clear':
        return (weatherTime != null && usesNightArt(weatherTime))
            ? Icons.nightlight_round
            : Icons.wb_sunny;
      case 'cloudy':
        return Icons.wb_cloudy;
      case 'overcast':
        return Icons.cloud;
      case 'fog':
        return Icons.foggy;
      case 'drizzle':
        return Icons.grain;
      case 'rain':
        return Icons.water_drop;
      case 'snow':
      case 'hail':
        return Icons.ac_unit;
      case 'thunderstorm':
        return Icons.flash_on;
      default:
        return Icons.thermostat;
    }
  }

  /// Accent color for weather-type icons on the map chrome.
  static Color weatherIconColor(String type, {String? weatherTime}) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'clear':
        return (weatherTime != null && usesNightArt(weatherTime))
            ? const Color(0xFFC5CAE9)
            : const Color(0xFFFFC107);
      case 'cloudy':
        return const Color(0xFFB0BEC5);
      case 'overcast':
        return const Color(0xFF90A4AE);
      case 'fog':
        return const Color(0xFFCFD8DC);
      case 'drizzle':
        return const Color(0xFF80DEEA);
      case 'rain':
        return const Color(0xFF4FC3F7);
      case 'snow':
        return const Color(0xFFE3F2FD);
      case 'hail':
        return const Color(0xFFB3E5FC);
      case 'thunderstorm':
        return const Color(0xFFFFEE58);
      default:
        return const Color(0xFFF8F4EC);
    }
  }

  static String weatherLabel(String type) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'clear':
        return 'Clear';
      case 'cloudy':
        return 'Partly cloudy';
      case 'overcast':
        return 'Overcast';
      case 'fog':
        return 'Fog';
      case 'drizzle':
        return 'Drizzle';
      case 'rain':
        return 'Rain';
      case 'snow':
        return 'Snow';
      case 'thunderstorm':
        return 'Thunderstorm';
      case 'hail':
        return 'Hail';
      default:
        return 'Unknown';
    }
  }

  static String timeLabel(String period) {
    switch (period) {
      case 'dawn':
        return 'Dawn';
      case 'dusk':
        return 'Dusk';
      case 'golden_hour':
        return 'Golden hour';
      case 'night':
        return 'Nighttime';
      case 'day':
      default:
        return 'Daytime';
    }
  }

  /// Period label with local clock time, e.g. `Daytime · 14:32`.
  static String timeLabelWithClock(String period, {DateTime? at}) {
    final clock = DateFormat.Hm().format((at ?? DateTime.now()).toLocal());
    return '${timeLabel(period)} · $clock';
  }

  static String paramLabel(String paramKey) {
    const labels = <String, String>{
      'discovery_distance_m': 'Discovery distance',
      'discovery_chance': 'Discovery chance',
      'rival_discovery_chance': 'Rival discovery chance',
      'documentation_distance_m': 'Documentation distance',
      'discovery_speed': 'Discovery speed',
      'discovery_max_speed_kmh': 'Discovery max speed',
      'discover_site_xp': 'Discover site',
      'discover_site_as_first_xp': 'Discover site as first',
      'disguise_of_site_xp': 'Disguise of site',
      'document_site_xp': 'Document site',
      'identify_site_xp': 'Identify site',
      'document_site_as_first_xp': 'Document site as first',
      'explore_100m_actively_xp': 'Explore 100m actively',
      'explore_100m_passively_xp': 'Explore 100m passively',
      'locate_fossil_in_situ_xp': 'Locate fossil in situ',
      'documentation_accuracy': 'Documentation accuracy',
    };
    return labels[paramKey] ??
        paramKey
            .split('_')
            .where((p) => p.isNotEmpty)
            .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
  }

  /// Field Survey skill params in skill-drawer order.
  static const fieldSurveySkillParamKeys = <String>[
    'discovery_distance_m',
    'discovery_chance',
    'discovery_max_speed_kmh',
    'documentation_distance_m',
    'discovery_speed',
    'documentation_accuracy',
    'rival_discovery_chance',
  ];

  /// Field Survey XP sources in skill-drawer order.
  static const fieldSurveyXpParamKeys = <String>[
    'explore_100m_actively_xp',
    'explore_100m_passively_xp',
    'discover_site_xp',
    'discover_site_as_first_xp',
    'identify_site_xp',
    'document_site_xp',
    'document_site_as_first_xp',
    'disguise_of_site_xp',
  ];

  static String formatModifierShort({
    required String op,
    required double value,
  }) {
    switch (op) {
      case 'replace':
        return '→ ${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2)}';
      case 'add':
        final abs = value.abs();
        final formatted = abs == abs.roundToDouble()
            ? abs.toStringAsFixed(0)
            : abs.toStringAsFixed(2);
        return value >= 0 ? '+$formatted' : '-$formatted';
      case 'multiply':
        // Relative to identity (×1.0): 1.3 → +30%, 0.9 → -10%.
        final deltaPct = (value - 1.0) * 100;
        final rounded = deltaPct.round();
        if (rounded == 0) return '±0%';
        return rounded > 0 ? '+$rounded%' : '$rounded%';
      default:
        return '$op $value';
    }
  }
}
