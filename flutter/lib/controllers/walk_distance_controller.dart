import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/health_distance_service.dart';

/// Owns walked-distance totals from Health and syncs them to the backend.
class WalkDistanceController extends ChangeNotifier {
  WalkDistanceController({
    HealthDistanceService? healthService,
    ApiClient? apiClient,
  })  : _health = healthService ?? HealthDistanceService(),
        _api = apiClient ?? ApiClient.instance;

  final HealthDistanceService _health;
  final ApiClient _api;

  double? _totalMeters;
  double? _weeklyMeters;
  HealthDistancePermission _permission = HealthDistancePermission.unknown;
  DateTime? _lastSyncedAt;
  bool _loading = false;
  String? _error;
  DateTime? _lastRefreshAt;
  Future<void>? _inFlight;

  double? get totalMeters => _totalMeters;
  double? get weeklyMeters => _weeklyMeters;
  HealthDistancePermission get permission => _permission;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasLiveHealthData =>
      _permission == HealthDistancePermission.granted &&
      _totalMeters != null &&
      _weeklyMeters != null;

  /// Seed displayed values from the server profile (cross-device fallback).
  void applyProfile(Profile? profile) {
    if (profile == null) return;
    var changed = false;
    if (_totalMeters == null && profile.totalDistanceM > 0) {
      _totalMeters = profile.totalDistanceM;
      changed = true;
    }
    if (_weeklyMeters == null && profile.weeklyDistanceM > 0) {
      _weeklyMeters = profile.weeklyDistanceM;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Refresh from Health (optionally requesting permission) and sync to API.
  Future<void> refresh({
    required Profile? profile,
    bool requestPermissionIfNeeded = false,
    bool force = false,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _refresh(
      profile: profile,
      requestPermissionIfNeeded: requestPermissionIfNeeded,
      force: force,
    );
    _inFlight = future.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<void> _refresh({
    required Profile? profile,
    required bool requestPermissionIfNeeded,
    required bool force,
  }) async {
    if (profile == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 30)) {
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      var status = await _health.checkPermission();
      if (status == HealthDistancePermission.unsupported ||
          status == HealthDistancePermission.unavailable) {
        _permission = status;
        applyProfile(profile);
        return;
      }

      if (status != HealthDistancePermission.granted &&
          requestPermissionIfNeeded) {
        final granted = await _health.requestAuthorization();
        status = granted
            ? HealthDistancePermission.granted
            : HealthDistancePermission.denied;
      }

      _permission = status;
      if (status != HealthDistancePermission.granted) {
        applyProfile(profile);
        return;
      }

      final start = profile.createdAt ?? now.subtract(const Duration(days: 365));
      final weekStart = localWeekStartMonday(now);
      final total = await _health.distanceMeters(start: start, end: now);
      final weekly = await _health.distanceMeters(start: weekStart, end: now);
      if (total == null || weekly == null) {
        _error = 'Could not read walking distance from Health.';
        applyProfile(profile);
        return;
      }

      _totalMeters = total;
      _weeklyMeters = weekly;
      _lastRefreshAt = now;
      notifyListeners();

      await _syncToBackend(
        totalMeters: total,
        weeklyMeters: weekly,
        weekStart: weekStartIso(now),
      );
    } catch (error) {
      _error = error.toString();
      if (kDebugMode) {
        debugPrint('WalkDistanceController.refresh: $error');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _syncToBackend({
    required double totalMeters,
    required double weeklyMeters,
    required String weekStart,
  }) async {
    try {
      final response = await _api.patch(
        '/api/v1/users/me/distance',
        body: {
          'total_distance_m': totalMeters,
          'weekly_distance_m': weeklyMeters,
          'week_start': weekStart,
        },
      );
      _lastSyncedAt = DateTime.now();
      final serverTotal = (response['total_distance_m'] as num?)?.toDouble();
      final serverWeekly = (response['weekly_distance_m'] as num?)?.toDouble();
      if (serverTotal != null) _totalMeters = serverTotal;
      if (serverWeekly != null) _weeklyMeters = serverWeekly;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('WalkDistanceController.sync: $error');
      }
      // Keep local Health values even if sync fails.
    }
  }
}
