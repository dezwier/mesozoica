import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/weather_controller.dart';
import '../models/weather_status.dart';
import '../widgets/weather/weather_detail_sheet.dart';
import '../widgets/weather/weather_display.dart';

/// Compact weather report on the map (under notifications; no panel chrome).
class MapWeatherChip extends StatelessWidget {
  const MapWeatherChip({super.key});

  /// Icon + temp row and type label (+ tap padding).
  static const double height = 40;

  static const _textShadows = <Shadow>[
    Shadow(
      color: Color(0x66000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<WeatherController>(
      builder: (context, weather, _) {
        final status = weather.status;
        if (status == null) return const SizedBox.shrink();
        return _WeatherChipBody(status: status);
      },
    );
  }
}

class _WeatherChipBody extends StatelessWidget {
  const _WeatherChipBody({required this.status});

  final WeatherStatus status;

  @override
  Widget build(BuildContext context) {
    final temp = status.temperatureC.round();
    final tempLabel =
        status.weatherType == 'unknown' && status.observedAt == null
            ? '—'
            : '$temp°';
    final iconColor = WeatherDisplay.weatherIconColor(
      status.weatherType,
      weatherTime: status.weatherTime,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showWeatherDetailSheet(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    WeatherDisplay.weatherIcon(
                      status.weatherType,
                      weatherTime: status.weatherTime,
                    ),
                    size: 18,
                    color: iconColor,
                    shadows: MapWeatherChip._textShadows,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tempLabel,
                    style: const TextStyle(
                      color: Color(0xFFF8F4EC),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      shadows: MapWeatherChip._textShadows,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                WeatherDisplay.weatherLabel(status.weatherType),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  shadows: MapWeatherChip._textShadows,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
