/// Hourly past + forecast series from GET /api/v1/weather/forecast.
class WeatherHourPoint {
  const WeatherHourPoint({
    required this.validAt,
    required this.weatherType,
    required this.temperatureC,
    required this.wmoCode,
    required this.isForecast,
    this.fetchedAt,
  });

  final DateTime validAt;
  final String weatherType;
  final double temperatureC;
  final int wmoCode;
  final bool isForecast;
  final DateTime? fetchedAt;

  factory WeatherHourPoint.fromJson(Map<String, dynamic> json) {
    var type = json['weather_type'] as String? ?? 'unknown';
    if (type == 'sunny') type = 'clear';
    return WeatherHourPoint(
      validAt:
          DateTime.tryParse(json['valid_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      weatherType: type,
      temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0,
      wmoCode: (json['wmo_code'] as num?)?.toInt() ?? -1,
      isForecast: json['is_forecast'] as bool? ?? false,
      fetchedAt: json['fetched_at'] != null
          ? DateTime.tryParse(json['fetched_at'] as String)
          : null,
    );
  }
}

class WeatherForecastCell {
  const WeatherForecastCell({
    required this.i,
    required this.j,
    required this.centerLat,
    required this.centerLon,
  });

  final int i;
  final int j;
  final double centerLat;
  final double centerLon;

  factory WeatherForecastCell.fromJson(Map<String, dynamic> json) {
    return WeatherForecastCell(
      i: (json['i'] as num?)?.toInt() ?? 0,
      j: (json['j'] as num?)?.toInt() ?? 0,
      centerLat: (json['center_lat'] as num?)?.toDouble() ?? 0,
      centerLon: (json['center_lon'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WeatherForecast {
  const WeatherForecast({required this.cell, required this.hours});

  final WeatherForecastCell cell;
  final List<WeatherHourPoint> hours;

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    final rawHours = json['hours'] as List<dynamic>? ?? const [];
    final cellJson = json['cell'] as Map<String, dynamic>? ?? const {};
    return WeatherForecast(
      cell: WeatherForecastCell.fromJson(cellJson),
      hours: [
        for (final item in rawHours)
          if (item is Map<String, dynamic>) WeatherHourPoint.fromJson(item),
      ],
    );
  }

  /// Hours at or before [now] (inclusive), oldest first.
  List<WeatherHourPoint> pastHours([DateTime? now]) {
    final when = (now ?? DateTime.now()).toUtc();
    return [
      for (final h in hours)
        if (!h.validAt.toUtc().isAfter(when)) h,
    ];
  }

  /// Hours strictly after [now], oldest first.
  List<WeatherHourPoint> forecastHours([DateTime? now]) {
    final when = (now ?? DateTime.now()).toUtc();
    return [
      for (final h in hours)
        if (h.validAt.toUtc().isAfter(when)) h,
    ];
  }
}
