import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/weather_controller.dart';
import '../models/weather_status.dart';
import '../theme/map_chrome_decorations.dart';
import '../theme/map_chrome_theme.dart';
import '../widgets/weather/weather_detail_sheet.dart';
import '../widgets/weather/weather_display.dart';

/// Compact weather report under the profile HUD.
class MapWeatherChip extends StatelessWidget {
  const MapWeatherChip({super.key});

  static const double height = 28;

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
    final tempLabel = status.weatherType == 'unknown' && status.observedAt == null
        ? '—'
        : '$temp°';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showWeatherDetailSheet(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: MapWeatherChip.height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: MapChromeDecorations.leatherPanel(
            borderRadius: BorderRadius.circular(14),
            soft: true,
            borderWidth: 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                WeatherDisplay.weatherIcon(status.weatherType),
                size: 14,
                color: const Color(0xFFF8F4EC),
              ),
              const SizedBox(width: 6),
              Text(
                tempLabel,
                style: const TextStyle(
                  color: Color(0xFFF8F4EC),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: MapChromeTheme.serifFont,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 12,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              Text(
                WeatherDisplay.timeLabel(status.weatherTime),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
