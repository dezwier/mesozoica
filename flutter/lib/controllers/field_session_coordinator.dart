import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

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

  final SiteService _siteService;
  LocationService? _locationService;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _sessionActive = false;
  bool _ensureInFlight = false;
  LatLng? _lastEnsurePosition;
  String? _pendingEnsureReason;
  VoidCallback? _locationListener;

  bool get isSessionActive => _sessionActive;

  void bind({required LocationService locationService}) {
    if (_locationService != null) {
      return;
    }

    _locationService = locationService;
    unawaited(() async {
      await _syncSession();
      _locationListener = () => _onLocationChanged(locationService);
      locationService.addListener(_locationListener!);
      if (_lifecycle == AppLifecycleState.resumed) {
        await _maybeEnsure(force: true, reason: reasonResume);
      }
    }());
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
    unawaited(_locationService?.onAppResumed());
    unawaited(() async {
      await _syncSession();
      await _maybeEnsure(force: true, reason: reasonResume);
    }());
  }

  void onBackground() {
    if (_lifecycle == AppLifecycleState.detached) {
      return;
    }
    _lifecycle = AppLifecycleState.paused;
    unawaited(_syncSession());
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
    final backgroundPreferred = _lifecycle != AppLifecycleState.resumed;
    await locationService.setFieldSession(
      active: true,
      backgroundPreferred: backgroundPreferred,
    );
  }

  Future<void> _maybeEnsure({
    LatLng? position,
    bool force = false,
    required String reason,
  }) async {
    if (!_sessionActive) return;
    if (_ensureInFlight) return;

    final location = position ?? _locationService?.currentLocation;
    if (location == null) {
      if (force) {
        _pendingEnsureReason = reason;
        _logEnsure(
          'deferred reason=$reason (waiting for GPS)',
        );
      }
      return;
    }

    _pendingEnsureReason = null;
    if (!force &&
        _lastEnsurePosition != null &&
        _distance(_lastEnsurePosition!, location) < ensureMoveThresholdM) {
      return;
    }

    _ensureInFlight = true;
    _lastEnsurePosition = location;

    try {
      final response = await _siteService.requestFieldSiteEnsure(
        lat: location.latitude,
        lon: location.longitude,
        radiusKm: nearbyRadiusKm,
        reason: reason,
      );
      _logEnsure(
        'check reason=$reason existing=${response.existingInRadius} '
        'missing=${response.missing} enqueued=${response.accepted} written=0',
      );
    } catch (error) {
      _logEnsure('failed reason=$reason error=$error');
    } finally {
      _ensureInFlight = false;
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
