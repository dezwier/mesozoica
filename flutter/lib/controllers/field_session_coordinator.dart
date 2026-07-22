import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';

/// Orchestrates field-site ensure calls across app lifecycle.
class FieldSessionCoordinator extends ChangeNotifier {
  FieldSessionCoordinator({SiteService? siteService})
      : _siteService = siteService ?? SiteService();

  static double get ensureMoveThresholdM =>
      GameConfig.instance.siteGeneration.client.ensureMoveThresholdM;
  static double get nearbyRadiusKm =>
      GameConfig.instance.siteGeneration.client.nearbyRadiusKm;

  static const reasonResume = 'resume';
  static const reasonMove500m = 'move_500m';
  static const reasonScan = 'scan';

  final SiteService _siteService;
  LocationService? _locationService;
  VoidCallback? _onEnsureScheduled;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _sessionActive = false;
  bool _ensureInFlight = false;
  LatLng? _lastEnsurePosition;
  String? _pendingEnsureReason;
  VoidCallback? _locationListener;
  bool _openedEnsureDone = false;

  bool get isSessionActive => _sessionActive;

  void bind({
    required LocationService locationService,
    VoidCallback? onEnsureScheduled,
  }) {
    if (_locationService != null) {
      _onEnsureScheduled = onEnsureScheduled;
      return;
    }

    _locationService = locationService;
    _onEnsureScheduled = onEnsureScheduled;
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
    // Stop GPS while backgrounded; walked distance comes from Health instead.
    unawaited(_enterBackground());
  }

  Future<void> _enterBackground() async {
    await _syncSession();
    await _locationService?.onAppBackgrounded();
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
    // Foreground-only GPS for proximity discovery + field ensure on every tab
    // while the app is open (Pokémon GO style; no background location).
    await locationService.setFieldSession(active: true);
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
        'enqueued reason=$reason accepted=${response.accepted}',
      );
      _onEnsureScheduled?.call();
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
