import 'dart:math' as math;

/// A GPS sample used for speed-filtered odometry (Pokémon GO style).
class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters,
    this.speedMps,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Horizontal accuracy in meters (smaller is better). Null if unknown.
  final double? accuracyMeters;

  /// Platform-reported speed in m/s when available.
  final double? speedMps;
}

/// Result of feeding one GPS fix into [GpsOdometer].
class GpsOdometerResult {
  const GpsOdometerResult({
    required this.acceptedMeters,
    required this.accepted,
    this.rejectReason,
  });

  final double acceptedMeters;
  final bool accepted;
  final String? rejectReason;
}

/// Speed / quality filtered GPS odometry for foreground walking distance.
class GpsOdometer {
  GpsOdometer({
    this.maxAccuracyMeters = 40,
    this.minDtSeconds = 0.5,
    this.maxDtSeconds = 60,
    this.maxSegmentMeters = 80,
    this.maxSpeedMps = 5.56, // 20 km/h
  });

  final double maxAccuracyMeters;
  final double minDtSeconds;
  final double maxDtSeconds;
  final double maxSegmentMeters;

  /// Max credited travel speed (m/s). Mutable so tool buffs can raise it.
  double maxSpeedMps;

  GpsFix? _previous;

  /// Clear the previous fix (e.g. when the app backgrounds).
  void reset() {
    _previous = null;
  }

  /// Feed a new fix. Returns meters to credit (0 when rejected / first fix).
  GpsOdometerResult addFix(GpsFix fix) {
    final previous = _previous;
    _previous = fix;

    if (previous == null) {
      return const GpsOdometerResult(acceptedMeters: 0, accepted: false);
    }

    final accuracy = fix.accuracyMeters;
    if (accuracy == null || accuracy > maxAccuracyMeters) {
      return GpsOdometerResult(
        acceptedMeters: 0,
        accepted: false,
        rejectReason: 'accuracy',
      );
    }

    final dt = fix.timestamp.difference(previous.timestamp).inMilliseconds /
        1000.0;
    if (dt < minDtSeconds || dt > maxDtSeconds) {
      return GpsOdometerResult(
        acceptedMeters: 0,
        accepted: false,
        rejectReason: 'dt',
      );
    }

    final distance = haversineMeters(
      previous.latitude,
      previous.longitude,
      fix.latitude,
      fix.longitude,
    );
    if (distance > maxSegmentMeters) {
      return GpsOdometerResult(
        acceptedMeters: 0,
        accepted: false,
        rejectReason: 'jump',
      );
    }

    final derivedSpeed = distance / dt;
    if (derivedSpeed > maxSpeedMps) {
      return GpsOdometerResult(
        acceptedMeters: 0,
        accepted: false,
        rejectReason: 'speed',
      );
    }

    final platformSpeed = fix.speedMps;
    if (platformSpeed != null &&
        platformSpeed >= 0 &&
        platformSpeed > maxSpeedMps) {
      return GpsOdometerResult(
        acceptedMeters: 0,
        accepted: false,
        rejectReason: 'platform_speed',
      );
    }

    return GpsOdometerResult(acceptedMeters: distance, accepted: true);
  }
}

/// Great-circle distance in meters between two WGS84 points.
double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;
