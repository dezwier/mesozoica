import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mesozoica/controllers/weather_controller.dart';
import 'package:mesozoica/models/weather_forecast.dart';
import 'package:mesozoica/models/weather_status.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/widgets/weather/weather_detail_sheet.dart';
import 'package:mesozoica/widgets/weather/weather_timeline_page.dart';

void main() {
  group('WeatherForecast parsing', () {
    test('fromJson maps hours and normalizes sunny', () {
      final forecast = WeatherForecast.fromJson({
        'cell': {
          'i': 1,
          'j': 2,
          'center_lat': 50.85,
          'center_lon': 4.35,
        },
        'hours': [
          {
            'valid_at': '2026-08-05T10:00:00Z',
            'weather_type': 'sunny',
            'temperature_c': 18.5,
            'wmo_code': 0,
            'is_forecast': false,
            'fetched_at': '2026-08-05T12:00:00Z',
          },
          {
            'valid_at': '2026-08-05T14:00:00Z',
            'weather_type': 'rain',
            'temperature_c': 16.0,
            'wmo_code': 61,
            'is_forecast': true,
            'fetched_at': '2026-08-05T12:00:00Z',
          },
        ],
      });

      expect(forecast.cell.i, 1);
      expect(forecast.cell.j, 2);
      expect(forecast.hours, hasLength(2));
      expect(forecast.hours.first.weatherType, 'clear');
      expect(forecast.hours.first.temperatureC, 18.5);
      expect(forecast.hours.last.isForecast, isTrue);
    });

    test('pastHours and forecastHours split around now', () {
      final now = DateTime.utc(2026, 8, 5, 12);
      final forecast = WeatherForecast(
        cell: const WeatherForecastCell(
          i: 0,
          j: 0,
          centerLat: 0,
          centerLon: 0,
        ),
        hours: [
          WeatherHourPoint(
            validAt: DateTime.utc(2026, 8, 5, 10),
            weatherType: 'clear',
            temperatureC: 10,
            wmoCode: 0,
            isForecast: false,
          ),
          WeatherHourPoint(
            validAt: DateTime.utc(2026, 8, 5, 12),
            weatherType: 'cloudy',
            temperatureC: 12,
            wmoCode: 2,
            isForecast: false,
          ),
          WeatherHourPoint(
            validAt: DateTime.utc(2026, 8, 5, 15),
            weatherType: 'rain',
            temperatureC: 11,
            wmoCode: 61,
            isForecast: true,
          ),
        ],
      );

      final past = forecast.pastHours(now);
      final future = forecast.forecastHours(now);
      expect(past, hasLength(2));
      expect(past.last.weatherType, 'cloudy');
      expect(future, hasLength(1));
      expect(future.first.weatherType, 'rain');
    });
  });

  test('sharedTempRange spans past and forecast', () {
    final past = [
      WeatherHourPoint(
        validAt: DateTime.utc(2026, 8, 5, 10),
        weatherType: 'clear',
        temperatureC: 5,
        wmoCode: 0,
        isForecast: false,
      ),
    ];
    final future = [
      WeatherHourPoint(
        validAt: DateTime.utc(2026, 8, 6, 10),
        weatherType: 'rain',
        temperatureC: 25,
        wmoCode: 61,
        isForecast: true,
      ),
    ];
    final range = WeatherTimelinePage.sharedTempRange([past, future]);
    expect(range, isNotNull);
    expect(range!.$1, lessThan(5));
    expect(range.$2, greaterThan(25));
  });

  testWidgets('WeatherTimelinePage shows title without scrub footer',
      (tester) async {
    final hours = [
      WeatherHourPoint(
        validAt: DateTime.utc(2026, 8, 5, 10),
        weatherType: 'rain',
        temperatureC: 12,
        wmoCode: 61,
        isForecast: false,
      ),
      WeatherHourPoint(
        validAt: DateTime.utc(2026, 8, 5, 11),
        weatherType: 'clear',
        temperatureC: 14,
        wmoCode: 0,
        isForecast: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: WeatherTimelinePage(
              title: 'Past 48 hours',
              hours: hours,
              loading: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Past 48 hours'), findsOneWidget);
    // Default selection is the latest past hour (clear) until the user scrubs.
    expect(find.textContaining('Clear'), findsOneWidget);
    expect(find.textContaining('14°'), findsOneWidget);
  });

  testWidgets('WeatherDetailDrawer period tabs switch Past / Current / Forecast',
      (tester) async {
    final location = LocationService();
    final seeded = _SeededWeatherController(locationService: location);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WeatherController>.value(value: seeded),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const WeatherDetailDrawer(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Forecast'), findsOneWidget);
    expect(find.text('Clear'), findsWidgets);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('Past 48 hours'), findsOneWidget);

    await tester.tap(find.text('Forecast'));
    await tester.pumpAndSettle();
    expect(find.text('Next 3 days'), findsOneWidget);

    seeded.dispose();
    location.dispose();
  });
}

class _SeededWeatherController extends WeatherController {
  _SeededWeatherController({required super.locationService}) {
    // ignore: invalid_use_of_protected_member
    // Seed via overriding getters.
  }

  @override
  WeatherStatus? get status => const WeatherStatus(
        weatherType: 'clear',
        temperatureC: 19,
        weatherTime: 'day',
      );

  @override
  WeatherForecast? get forecast => WeatherForecast(
        cell: const WeatherForecastCell(
          i: 0,
          j: 0,
          centerLat: 50.85,
          centerLon: 4.35,
        ),
        hours: [
          WeatherHourPoint(
            validAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
            weatherType: 'rain',
            temperatureC: 15,
            wmoCode: 61,
            isForecast: false,
          ),
          WeatherHourPoint(
            validAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
            weatherType: 'cloudy',
            temperatureC: 17,
            wmoCode: 2,
            isForecast: true,
          ),
        ],
      );

  @override
  bool get isForecastLoading => false;
}
