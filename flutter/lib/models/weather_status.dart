/// Ambient weather status for HUD + gameplay modifiers.
class WeatherStatus {
  const WeatherStatus({
    required this.weatherType,
    required this.temperatureC,
    required this.weatherTime,
    this.observedAt,
  });

  final String weatherType;
  final double temperatureC;
  /// Solar period: dawn | day | dusk | night.
  final String weatherTime;
  final DateTime? observedAt;

  WeatherStatus copyWith({
    String? weatherType,
    double? temperatureC,
    String? weatherTime,
    DateTime? observedAt,
  }) {
    return WeatherStatus(
      weatherType: weatherType ?? this.weatherType,
      temperatureC: temperatureC ?? this.temperatureC,
      weatherTime: weatherTime ?? this.weatherTime,
      observedAt: observedAt ?? this.observedAt,
    );
  }

  factory WeatherStatus.fromJson(Map<String, dynamic> json) {
    return WeatherStatus(
      weatherType: json['weather_type'] as String? ?? 'unknown',
      temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0,
      weatherTime: json['weather_time'] as String? ?? 'day',
      observedAt: json['observed_at'] != null
          ? DateTime.tryParse(json['observed_at'] as String)
          : null,
    );
  }
}
