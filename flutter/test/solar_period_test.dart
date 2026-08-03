import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/utils/solar_period.dart';

void main() {
  // Brussels
  const lat = 50.85;
  const lng = 4.35;

  group('Solar.elevationDegrees', () {
    test('midday summer is high above horizon', () {
      // 12:00 CEST = 10:00 UTC on 2026-07-20
      final elev = Solar.elevationDegrees(
        latitude: lat,
        longitude: lng,
        at: DateTime.utc(2026, 7, 20, 10),
      );
      expect(elev, greaterThan(50));
    });

    test('midnight summer is below horizon', () {
      final elev = Solar.elevationDegrees(
        latitude: lat,
        longitude: lng,
        at: DateTime.utc(2026, 7, 20, 22),
      );
      expect(elev, lessThan(-6));
    });
  });

  group('Solar.periodAt', () {
    test('summer evening still day in Brussels', () {
      // 18:00 CEST = 16:00 UTC — sun still well up in July (≥ 6°)
      expect(
        Solar.periodAt(
          latitude: lat,
          longitude: lng,
          at: DateTime.utc(2026, 7, 20, 16),
        ),
        SolarPeriod.day,
      );
      expect(
        Solar.lightPresetAt(
          latitude: lat,
          longitude: lng,
          at: DateTime.utc(2026, 7, 20, 16),
        ),
        'day',
      );
    });

    test('summer late evening is golden hour then dusk then night', () {
      // Near sunset elevation band (0–6°) then civil dusk then night
      expect(
        Solar.periodAt(
          latitude: lat,
          longitude: lng,
          at: DateTime.utc(2026, 7, 20, 19, 45),
        ),
        anyOf(SolarPeriod.day, SolarPeriod.golden_hour, SolarPeriod.dusk),
      );
      expect(
        Solar.periodAt(
          latitude: lat,
          longitude: lng,
          at: DateTime.utc(2026, 7, 20, 22),
        ),
        SolarPeriod.night,
      );
    });

    test('golden hour maps lightPreset to day', () {
      DateTime? sample;
      for (var hour = 17; hour <= 20; hour++) {
        for (final minute in [0, 15, 30, 45]) {
          final when = DateTime.utc(2026, 7, 20, hour, minute);
          final elev = Solar.elevationDegrees(
            latitude: lat,
            longitude: lng,
            at: when,
          );
          if (elev >= 0 && elev < 6) {
            sample = when;
            break;
          }
        }
        if (sample != null) break;
      }
      expect(sample, isNotNull);
      expect(
        Solar.periodAt(latitude: lat, longitude: lng, at: sample!),
        SolarPeriod.golden_hour,
      );
      expect(
        Solar.lightPresetAt(latitude: lat, longitude: lng, at: sample),
        'day',
      );
    });

    test('winter late afternoon is night or dusk', () {
      // 17:00 CET = 16:00 UTC on Dec 21 — after sunset in Brussels
      expect(
        Solar.periodAt(
          latitude: lat,
          longitude: lng,
          at: DateTime.utc(2026, 12, 21, 16),
        ),
        anyOf(SolarPeriod.dusk, SolarPeriod.night),
      );
    });

    test('winter morning civil twilight is dawn', () {
      final events = Solar.eventsForDay(
        latitude: lat,
        longitude: lng,
        day: DateTime.utc(2026, 12, 21),
      );
      expect(events.civilDawn, isNotNull);
      expect(events.sunrise, isNotNull);
      final midTwilight = events.civilDawn!.add(
        Duration(
          milliseconds: events.sunrise!
                  .difference(events.civilDawn!)
                  .inMilliseconds ~/
              2,
        ),
      );
      expect(
        Solar.periodAt(latitude: lat, longitude: lng, at: midTwilight),
        SolarPeriod.dawn,
      );
    });
  });

  group('Solar.eventsForDay', () {
    test('Brussels July order and long day', () {
      final events = Solar.eventsForDay(
        latitude: lat,
        longitude: lng,
        day: DateTime.utc(2026, 7, 20),
      );
      expect(events.civilDawn, isNotNull);
      expect(events.sunrise, isNotNull);
      expect(events.sunset, isNotNull);
      expect(events.civilDusk, isNotNull);
      expect(events.civilDawn!.isBefore(events.sunrise!), isTrue);
      expect(events.sunrise!.isBefore(events.sunset!), isTrue);
      expect(events.sunset!.isBefore(events.civilDusk!), isTrue);
      // Daylight longer than 15h in mid-July at ~51°N
      final daylight = events.sunset!.difference(events.sunrise!);
      expect(daylight.inHours, greaterThanOrEqualTo(15));
    });

    test('Brussels December shorter day', () {
      final events = Solar.eventsForDay(
        latitude: lat,
        longitude: lng,
        day: DateTime.utc(2026, 12, 21),
      );
      final daylight = events.sunset!.difference(events.sunrise!);
      expect(daylight.inHours, lessThan(9));
    });
  });
}
