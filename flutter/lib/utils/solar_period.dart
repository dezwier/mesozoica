import 'dart:math' as math;

/// Daylight phase from solar elevation (civil twilight + golden hour).
///
/// Thresholds match outdoor perception and Mapbox Standard `lightPreset`
/// names (golden hour maps to day for Mapbox):
/// - [day]: sun elevation ≥ 6°
/// - [golden_hour]: 0° ≤ elevation < 6°
/// - [dawn] / [dusk]: civil twilight (−6° ≤ elevation < 0°)
/// - [night]: sun below −6°
enum SolarPeriod { dawn, day, dusk, golden_hour, night }

/// Sunrise / sunset / civil-twilight times for a calendar day (UTC instants).
///
/// A field is `null` when that event does not occur (polar day / night).
class SolarDayEvents {
  const SolarDayEvents({
    this.civilDawn,
    this.sunrise,
    this.sunset,
    this.civilDusk,
  });

  final DateTime? civilDawn;
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? civilDusk;
}

/// Location-aware solar times (NOAA solar-position formulas).
///
/// Pure utility — no Flutter / GPS dependency. Pass phone coordinates for
/// map lighting, gameplay windows, etc.
class Solar {
  Solar._();

  /// Civil twilight lower bound (degrees above horizon).
  static const double civilTwilightElevationDeg = -6.0;

  /// Upper bound of golden hour (degrees above horizon).
  static const double goldenHourElevationDeg = 6.0;

  /// Geometric sunrise/sunset (refraction + solar disc), degrees.
  static const double sunriseElevationDeg = -0.833;

  /// Solar elevation in degrees at [latitude]/[longitude] for [at] (any zone).
  static double elevationDegrees({
    required double latitude,
    required double longitude,
    required DateTime at,
  }) {
    final utc = at.toUtc();
    final jc = _julianCentury(_julianDay(utc));
    final decl = _sunDeclinationRad(jc);
    final eqTime = _equationOfTimeMinutes(jc);
    final hourAngle = _hourAngleDegrees(utc, longitude, eqTime);
    final latRad = _rad(latitude);
    final cosZenith =
        math.sin(latRad) * math.sin(decl) +
        math.cos(latRad) * math.cos(decl) * math.cos(_rad(hourAngle));
    final zenith = _deg(math.acos(cosZenith.clamp(-1.0, 1.0)));
    return 90.0 - zenith;
  }

  /// Dawn / day / dusk / golden_hour / night at a point in time.
  static SolarPeriod periodAt({
    required double latitude,
    required double longitude,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now();
    final elev = elevationDegrees(
      latitude: latitude,
      longitude: longitude,
      at: when,
    );
    if (elev >= goldenHourElevationDeg) return SolarPeriod.day;
    if (elev >= 0) return SolarPeriod.golden_hour;
    if (elev >= civilTwilightElevationDeg) {
      final noon = solarNoonUtc(longitude: longitude, day: when.toUtc());
      return when.toUtc().isBefore(noon) ? SolarPeriod.dawn : SolarPeriod.dusk;
    }
    return SolarPeriod.night;
  }

  /// Mapbox Standard `lightPreset` string for [periodAt].
  ///
  /// Mapbox only supports dawn/day/dusk/night; golden hour uses day.
  static String lightPresetAt({
    required double latitude,
    required double longitude,
    DateTime? at,
  }) {
    final period = periodAt(latitude: latitude, longitude: longitude, at: at);
    return period == SolarPeriod.golden_hour ? 'day' : period.name;
  }

  /// Solar noon (sun on local meridian) for the UTC calendar day of [day].
  static DateTime solarNoonUtc({
    required double longitude,
    required DateTime day,
  }) {
    final utcDay = DateTime.utc(
      day.toUtc().year,
      day.toUtc().month,
      day.toUtc().day,
    );
    // First pass at 12:00 UTC, then refine with that day's equation of time.
    var jc = _julianCentury(_julianDay(utcDay.add(const Duration(hours: 12))));
    var eqTime = _equationOfTimeMinutes(jc);
    var noonMinutes = 720.0 - 4.0 * longitude - eqTime;
    var noon = utcDay.add(
      Duration(milliseconds: (noonMinutes * 60000).round()),
    );
    jc = _julianCentury(_julianDay(noon));
    eqTime = _equationOfTimeMinutes(jc);
    noonMinutes = 720.0 - 4.0 * longitude - eqTime;
    return utcDay.add(Duration(milliseconds: (noonMinutes * 60000).round()));
  }

  /// Civil dawn, sunrise, sunset, civil dusk for the UTC calendar day of [day].
  static SolarDayEvents eventsForDay({
    required double latitude,
    required double longitude,
    required DateTime day,
  }) {
    final utcDay = DateTime.utc(
      day.toUtc().year,
      day.toUtc().month,
      day.toUtc().day,
    );
    final noon = solarNoonUtc(longitude: longitude, day: utcDay);
    final jc = _julianCentury(_julianDay(noon));
    final decl = _sunDeclinationRad(jc);
    final eqTime = _equationOfTimeMinutes(jc);

    DateTime? atElevation(double elevDeg, {required bool morning}) {
      final ha = _hourAngleForElevation(
        latitude: latitude,
        declinationRad: decl,
        elevationDeg: elevDeg,
      );
      if (ha == null) return null;
      final minutes =
          720.0 - 4.0 * longitude - eqTime + (morning ? -ha : ha) * 4.0;
      return utcDay.add(Duration(milliseconds: (minutes * 60000).round()));
    }

    return SolarDayEvents(
      civilDawn: atElevation(civilTwilightElevationDeg, morning: true),
      sunrise: atElevation(sunriseElevationDeg, morning: true),
      sunset: atElevation(sunriseElevationDeg, morning: false),
      civilDusk: atElevation(civilTwilightElevationDeg, morning: false),
    );
  }

  // --- NOAA solar position helpers ---

  static double _julianDay(DateTime utc) {
    final y = utc.year;
    final m = utc.month;
    final d =
        utc.day +
        (utc.hour +
                utc.minute / 60.0 +
                (utc.second + utc.millisecond / 1000.0) / 3600.0) /
            24.0;
    var year = y;
    var month = m;
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        d +
        b -
        1524.5;
  }

  static double _julianCentury(double julianDay) =>
      (julianDay - 2451545.0) / 36525.0;

  static double _sunDeclinationRad(double jc) {
    final geomMeanLong = _geomMeanLongSunDeg(jc);
    final geomMeanAnom = _geomMeanAnomalySunDeg(jc);
    final sunEqOfCtr =
        math.sin(_rad(geomMeanAnom)) *
            (1.914602 - jc * (0.004817 + 0.000014 * jc)) +
        math.sin(_rad(2 * geomMeanAnom)) * (0.019993 - 0.000101 * jc) +
        math.sin(_rad(3 * geomMeanAnom)) * 0.000289;
    final sunTrueLong = geomMeanLong + sunEqOfCtr;
    final sunAppLong =
        sunTrueLong -
        0.00569 -
        0.00478 * math.sin(_rad(125.04 - 1934.136 * jc));
    final meanObliq =
        23.0 +
        (26.0 +
                (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) /
                    60.0) /
            60.0;
    final obliqCorr =
        meanObliq + 0.00256 * math.cos(_rad(125.04 - 1934.136 * jc));
    return math.asin(math.sin(_rad(obliqCorr)) * math.sin(_rad(sunAppLong)));
  }

  static double _equationOfTimeMinutes(double jc) {
    final geomMeanLong = _geomMeanLongSunDeg(jc);
    final geomMeanAnom = _geomMeanAnomalySunDeg(jc);
    final eccentEarth = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc);
    final meanObliq =
        23.0 +
        (26.0 +
                (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) /
                    60.0) /
            60.0;
    final obliqCorr =
        meanObliq + 0.00256 * math.cos(_rad(125.04 - 1934.136 * jc));
    final y = math.pow(math.tan(_rad(obliqCorr) / 2.0), 2).toDouble();
    final l0 = _rad(geomMeanLong);
    final e = eccentEarth;
    final m = _rad(geomMeanAnom);
    final eqRad =
        y * math.sin(2 * l0) -
        2 * e * math.sin(m) +
        4 * e * y * math.sin(m) * math.cos(2 * l0) -
        0.5 * y * y * math.sin(4 * l0) -
        1.25 * e * e * math.sin(2 * m);
    return 4.0 * _deg(eqRad);
  }

  static double _geomMeanLongSunDeg(double jc) {
    var l = (280.46646 + jc * (36000.76983 + 0.0003032 * jc)) % 360.0;
    if (l < 0) l += 360.0;
    return l;
  }

  static double _geomMeanAnomalySunDeg(double jc) =>
      357.52911 + jc * (35999.05029 - 0.0001537 * jc);

  static double _hourAngleDegrees(
    DateTime utc,
    double longitude,
    double eqTimeMinutes,
  ) {
    final minutes =
        utc.hour * 60.0 +
        utc.minute +
        utc.second / 60.0 +
        utc.millisecond / 60000.0;
    var trueSolar = minutes + eqTimeMinutes + 4.0 * longitude;
    trueSolar = trueSolar % 1440.0;
    if (trueSolar < 0) trueSolar += 1440.0;
    return trueSolar / 4.0 < 0
        ? trueSolar / 4.0 + 180.0
        : trueSolar / 4.0 - 180.0;
  }

  /// Absolute hour angle (degrees) when sun is at [elevationDeg], or null.
  static double? _hourAngleForElevation({
    required double latitude,
    required double declinationRad,
    required double elevationDeg,
  }) {
    final latRad = _rad(latitude);
    final zenithRad = _rad(90.0 - elevationDeg);
    final cosHa =
        (math.cos(zenithRad) / (math.cos(latRad) * math.cos(declinationRad))) -
        math.tan(latRad) * math.tan(declinationRad);
    if (cosHa < -1.0 || cosHa > 1.0) return null;
    return _deg(math.acos(cosHa.clamp(-1.0, 1.0)));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
  static double _deg(double rad) => rad * 180.0 / math.pi;
}
