import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Permission / availability state for HealthKit / Health Connect distance.
enum HealthDistancePermission {
  unsupported,
  unavailable,
  unknown,
  denied,
  granted,
}

/// Local Monday 00:00 for [moment] in the device timezone.
DateTime localWeekStartMonday([DateTime? moment]) {
  final now = moment ?? DateTime.now();
  final local = DateTime(now.year, now.month, now.day);
  // Dart weekday: Monday=1 … Sunday=7
  return local.subtract(Duration(days: local.weekday - DateTime.monday));
}

/// ISO date (yyyy-MM-dd) for [localWeekStartMonday].
String weekStartIso([DateTime? moment]) {
  final start = localWeekStartMonday(moment);
  final y = start.year.toString().padLeft(4, '0');
  final m = start.month.toString().padLeft(2, '0');
  final d = start.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Reads walking+running distance from Apple Health / Health Connect.
class HealthDistanceService {
  HealthDistanceService({Health? health}) : _health = health ?? Health();

  static const _types = [HealthDataType.DISTANCE_WALKING_RUNNING];

  final Health _health;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<HealthDistancePermission> checkPermission() async {
    if (!isSupportedPlatform) {
      return HealthDistancePermission.unsupported;
    }
    try {
      await _ensureConfigured();
      if (Platform.isAndroid) {
        final available = await _health.isHealthConnectAvailable();
        if (!available) {
          return HealthDistancePermission.unavailable;
        }
      }
      // On iOS, HealthKit never discloses READ grant status — hasPermissions
      // returns null → unknown. Callers must still attempt reads when unknown.
      final granted = await _health.hasPermissions(_types);
      if (granted == true) {
        return HealthDistancePermission.granted;
      }
      if (granted == false) {
        return HealthDistancePermission.denied;
      }
      return HealthDistancePermission.unknown;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('HealthDistanceService.checkPermission: $error');
      }
      return HealthDistancePermission.unavailable;
    }
  }

  /// Prompt the OS permission sheet. Returns whether read access was granted.
  Future<bool> requestAuthorization() async {
    if (!isSupportedPlatform) return false;
    try {
      await _ensureConfigured();
      if (Platform.isAndroid) {
        final available = await _health.isHealthConnectAvailable();
        if (!available) {
          await _health.installHealthConnect();
          return false;
        }
      }
      final granted = await _health.requestAuthorization(_types);
      if (granted && Platform.isAndroid) {
        // Needed to read walking distance older than ~30 days.
        try {
          final historyAvailable =
              await _health.isHealthDataHistoryAvailable();
          if (historyAvailable) {
            await _health.requestHealthDataHistoryAuthorization();
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              'HealthDistanceService.historyAuthorization: $error',
            );
          }
        }
      }
      return granted;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('HealthDistanceService.requestAuthorization: $error');
      }
      return false;
    }
  }

  /// Sum of walking+running distance in meters for [[start], [end]).
  ///
  /// Prefers HealthKit/Connect **statistics** (same merge as the Health app)
  /// so iPhone + Watch overlapping samples are not double-counted. Falls back
  /// to raw samples only if the statistics query fails.
  Future<double?> distanceMeters({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!isSupportedPlatform) return null;
    if (!end.isAfter(start)) return 0;
    try {
      await _ensureConfigured();
      if (Platform.isAndroid) {
        final available = await _health.isHealthConnectAvailable();
        if (!available) return null;
      }

      final fromStats = await _distanceFromStatistics(start: start, end: end);
      if (fromStats != null) return fromStats;

      return _distanceFromSamples(start: start, end: end);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('HealthDistanceService.distanceMeters: $error');
      }
      return null;
    }
  }

  /// HKStatisticsCollectionQuery / interval aggregate (deduped sources).
  Future<double?> _distanceFromStatistics({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final seconds = math.max(1, end.difference(start).inSeconds);
      final points = await _health.getHealthIntervalDataFromTypes(
        startDate: start,
        endDate: end,
        types: _types,
        interval: seconds,
      );
      var total = 0.0;
      for (final point in points) {
        final value = point.value;
        if (value is NumericHealthValue) {
          total += value.numericValue.toDouble();
        }
      }
      return total;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('HealthDistanceService.statistics: $error');
      }
      return null;
    }
  }

  Future<double?> _distanceFromSamples({
    required DateTime start,
    required DateTime end,
  }) async {
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: start,
      endTime: end,
    );
    final unique = _health.removeDuplicates(points);
    // Prefer a single source when phone + watch both reported the same walks
    // (statistics query unavailable). Pick the source with the largest sum.
    final bySource = <String, double>{};
    for (final point in unique) {
      final value = point.value;
      if (value is! NumericHealthValue) continue;
      final key = point.sourceId.isNotEmpty ? point.sourceId : point.sourceName;
      bySource[key] = (bySource[key] ?? 0) + value.numericValue.toDouble();
    }
    if (bySource.isEmpty) return 0;
    return bySource.values.reduce(math.max);
  }
}
