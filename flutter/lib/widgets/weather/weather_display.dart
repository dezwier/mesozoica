import 'package:flutter/material.dart';

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

  static String paramLabel(String paramKey) {
    const labels = <String, String>{
      'visibility_distance_m': 'Visibility distance',
      'discovery_chance': 'Discovery chance',
      'max_discovery_speed_kmh': 'Max discovery speed',
      'dino_accuracy': 'Dinosaur accuracy',
      'fossil_accuracy': 'Fossil accuracy',
      'completeness_accuracy': 'Completeness accuracy',
      'quality_accuracy': 'Quality accuracy',
      'depth_accuracy': 'Depth accuracy',
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
        if (value == value.roundToDouble()) {
          return '×${value.toStringAsFixed(0)}';
        }
        return '×${value.toStringAsFixed(2)}';
      default:
        return '$op $value';
    }
  }
}
