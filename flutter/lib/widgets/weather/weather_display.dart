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

  /// Night-side art for dusk + night; day-side art for dawn + day.
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

  static IconData weatherIcon(String type) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'clear':
        return Icons.wb_sunny_outlined;
      case 'cloudy':
        return Icons.wb_cloudy_outlined;
      case 'overcast':
        return Icons.cloud_outlined;
      case 'fog':
        return Icons.blur_on;
      case 'drizzle':
        return Icons.grain;
      case 'rain':
        return Icons.water_drop_outlined;
      case 'snow':
      case 'hail':
        return Icons.ac_unit;
      case 'thunderstorm':
        return Icons.flash_on_outlined;
      default:
        return Icons.thermostat_outlined;
    }
  }

  /// Accent color for weather-type icons on the map chrome.
  static Color weatherIconColor(String type) {
    switch (type == 'sunny' ? 'clear' : type) {
      case 'clear':
        return const Color(0xFFFFC107);
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
      case 'night':
        return 'Nighttime';
      case 'day':
      default:
        return 'Daytime';
    }
  }

  /// Period label with local clock time, e.g. `Daytime · 14:32`.
  static String timeLabelWithClock(
    String period, {
    DateTime? at,
  }) {
    final clock = DateFormat.Hm().format((at ?? DateTime.now()).toLocal());
    return '${timeLabel(period)} · $clock';
  }

  static String paramLabel(String paramKey) {
    const labels = <String, String>{
      'visibility_distance_m': 'Visibility distance',
      'discovery_chance': 'Discovery chance',
      'rival_discovery': 'Rival discovery',
      'site_visibility_m': 'Site visibility',
      'max_discovery_speed_kmh': 'Max discovery speed',
      'site_discovery_xp': 'Site discovery XP',
      'successful_site_disguise_xp': 'Site disguise',
      'site_exploration_xp': 'Site exploration XP',
      'site_documentation_xp': 'Site documentation',
      'active_km_xp': 'Active km XP',
      'passive_km_xp': 'Passive km XP',
      'fossil_discovery_xp': 'Fossil discovery XP',
      'dino_accuracy': 'Dinosaur count estimation',
      'fossil_accuracy': 'Fossil count estimation',
      'completeness_accuracy': 'Completeness estimation',
      'quality_accuracy': 'Fossil quality estimation',
      'depth_accuracy': 'Depth estimation',
    };
    return labels[paramKey] ??
        paramKey
            .split('_')
            .where((p) => p.isNotEmpty)
            .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
  }

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
