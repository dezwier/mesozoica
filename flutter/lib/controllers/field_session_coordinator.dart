import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';

/// Orchestrates field-site ensure calls across app lifecycle.
class FieldSessionCoordinator extends ChangeNotifier {
  FieldSessionCoordinator({SiteService? siteService})
      : _siteService = siteService ?? SiteService();

  static const ensureMoveThresholdM = 500.0;
  static const nearbyRadiusKm = 1.0;

  static const reasonResume = 'resume';
  static const reasonMove500m = 'move_500m';
  static const reasonScan = 'scan';

  final SiteService _siteService;
  LocationService? _locationService;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _sessionActive = false;
  bool _ensureInFlight = false;
  LatLng? _lastEnsurePosition;
  String? _pendingEnsureReason;
  VoidCallback? _locationListener;
  bool _openedEnsureDone = false;

  bool get isSessionActive => _sessionActive;

  void bind({required LocationService locationService}) {
    if (_locationService != null) {
      return;
    }

    _locationService = locationService;
    unawaited(_startSession());
  }

  Future<void> _startSession() async {
    final locationService = _locationService;
    if (locationService == null) {
      return;
    }

    _locationListener ??= () => _onLocationChanged(locationService);
    locationService.removeListener(_locationListener!);
    locationService.addListener(_locationListener!);
    if (_lifecycle == AppLifecycleState.resumed) {
      await _runResumeEnsure();
    } else {
      await _syncSession();
    }
  }

  Future<void> _runResumeEnsure() async {
    await _syncSession();
    await _locationService?.onAppResumed();
    await _maybeEnsure(force: true, reason: reasonResume);
    _openedEnsureDone = true;
  }

  void _onLocationChanged(LocationService locationService) {
    if (!_sessionActive) return;

    final pending = _pendingEnsureReason;
    if (pending != null && locationService.currentLocation != null) {
      _pendingEnsureReason = null;
      unawaited(_maybeEnsure(force: true, reason: pending));
      return;
    }

    final location = locationService.currentLocation;
    if (location == null) return;
    if (!_openedEnsureDone) return;
    unawaited(_maybeEnsure(position: location, reason: reasonMove500m));
  }

  void onLifecycle(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.detached) {
      stop();
      return;
    }
    unawaited(_syncSession());
  }

  void onForeground() {
    _lifecycle = AppLifecycleState.resumed;
    unawaited(_runResumeEnsure());
  }

  void onBackground() {
    if (_lifecycle == AppLifecycleState.detached) {
      return;
    }
    _lifecycle = AppLifecycleState.paused;
    unawaited(_syncSession());
  }

  /// Manual scan at a map-chosen point (field mode FAB).
  Future<FieldEnsureResponse?> scanAt(LatLng position) async {
    if (_lifecycle == AppLifecycleState.detached) {
      _logEnsure('scan skipped (app detached)');
      return null;
    }
    if (!_sessionActive) {
      await _syncSession();
    }
    if (!_sessionActive) {
      _logEnsure('scan skipped (session inactive)');
      return null;
    }
    return _maybeEnsure(position: position, force: true, reason: reasonScan);
  }

  void stop() {
    if (!_sessionActive) {
      return;
    }
    _sessionActive = false;
    _pendingEnsureReason = null;
    unawaited(_locationService?.setFieldSession(active: false));
  }

  Future<void> _syncSession() async {
    final locationService = _locationService;
    if (locationService == null) {
      return;
    }

    if (_lifecycle == AppLifecycleState.detached) {
      _sessionActive = false;
      await locationService.setFieldSession(active: false);
      return;
    }

    _sessionActive = true;
    // Foreground permission only — ensure runs on app open/resume and 500 m
    // moves while the process is alive; no iOS "Always" location required.
    await locationService.setFieldSession(
      active: true,
      backgroundPreferred: false,
    );
  }

  Future<FieldEnsureResponse?> _maybeEnsure({
    LatLng? position,
    bool force = false,
    required String reason,
  }) async {
    if (!_sessionActive) return null;
    if (_ensureInFlight) {
      if (force) {
        _pendingEnsureReason = reason;
      }
      return null;
    }
    final location = position ?? _locationService?.currentLocation;
    if (location == null) {
      if (force) {
        _pendingEnsureReason = reason;
        final err = _locationService?.error;
        _logEnsure(
          'deferred reason=$reason (waiting for GPS'
          '${err != null ? '; $err' : ''})',
        );
      }
      return null;
    }

    _pendingEnsureReason = null;
    if (!force &&
        _lastEnsurePosition != null &&
        _distance(_lastEnsurePosition!, location) < ensureMoveThresholdM) {
      return null;
    }

    _ensureInFlight = true;
    if (reason != reasonScan) {
      _lastEnsurePosition = location;
    }

    try {
      final response = await _siteService.requestFieldSiteEnsure(
        lat: location.latitude,
        lon: location.longitude,
        radiusKm: nearbyRadiusKm,
        reason: reason,
      );
      _logEnsure(
        'check reason=$reason existing=${response.existingInRadius} '
        'missing=${response.missing} enqueued=${response.accepted} '
        'written=0',
      );
      return response;
    } catch (error) {
      _logEnsure('failed reason=$reason error=$error');
      if (reason == reasonScan) {
        rethrow;
      }
      return null;
    } finally {
      _ensureInFlight = false;
      final pending = _pendingEnsureReason;
      if (pending != null) {
        _pendingEnsureReason = null;
        unawaited(_maybeEnsure(force: true, reason: pending));
      }
    }
  }

  final Distance _distance = const Distance();

  void _logEnsure(String message) {
    developer.log(
      'field_site_generate action=$message',
      name: 'field_site_generate',
    );
    if (kDebugMode) {
      debugPrint('FieldSessionCoordinator: $message');
    }
  }

  @override
  void dispose() {
    _locationService?.removeListener(_locationListener ?? () {});
    _siteService.dispose();
    super.dispose();
  }
}
