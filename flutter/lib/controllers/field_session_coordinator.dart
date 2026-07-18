import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/catalog_mode_controller.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';

/// Orchestrates field-site ensure calls across app lifecycle and tabs.
class FieldSessionCoordinator extends ChangeNotifier {
  FieldSessionCoordinator({SiteService? siteService})
      : _siteService = siteService ?? SiteService();

  static const ensureMoveThresholdM = 500.0;
  static const nearbyRadiusKm = 1.0;

  static const reasonResume = 'resume';
  static const reasonMove500m = 'move_500m';
  static const reasonFieldModeOn = 'field_mode_on';

  final SiteService _siteService;
  CatalogModeController? _catalogModeController;
  LocationService? _locationService;

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _sessionActive = false;
  bool _ensureInFlight = false;
  LatLng? _lastEnsurePosition;
  String? _pendingEnsureReason;
  VoidCallback? _locationListener;
  VoidCallback? _catalogListener;

  bool get isSessionActive => _sessionActive;

  void bind({
    required CatalogModeController catalogModeController,
    required LocationService locationService,
  }) {
    if (_catalogModeController != null) {
      return;
    }

    _catalogModeController = catalogModeController;
    _locationService = locationService;

    _catalogListener = () => unawaited(
          _syncSession(ensureReason: reasonFieldModeOn),
        );
    catalogModeController.addListener(_catalogListener!);
    unawaited(() async {
      await _syncSession(ensureReason: reasonFieldModeOn);
      _locationListener = () => _onLocationChanged(locationService);
      locationService.addListener(_locationListener!);
      _onLocationChanged(locationService);
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
    unawaited(_syncSession(ensureReason: reasonResume));
  }

  void onBackground() {
    if (_lifecycle == AppLifecycleState.detached) {
      return;
    }
    _lifecycle = AppLifecycleState.paused;
    unawaited(_syncSession());
  }

  void stop() {
    if (!_sessionActive && _catalogModeController?.isField != true) {
      return;
    }
    _sessionActive = false;
    _pendingEnsureReason = null;
    unawaited(_locationService?.setFieldSession(active: false));
  }

  Future<void> _syncSession({String? ensureReason}) async {
    final catalogMode = _catalogModeController;
    final locationService = _locationService;
    if (catalogMode == null || locationService == null) {
      return;
    }

    final shouldRun =
        catalogMode.isField && _lifecycle != AppLifecycleState.detached;
    if (!shouldRun) {
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
    if (_lifecycle == AppLifecycleState.resumed && ensureReason != null) {
      await _maybeEnsure(force: true, reason: ensureReason);
    }
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
        if (kDebugMode) {
          debugPrint(
            'FieldSessionCoordinator: deferred ensure reason=$reason '
            '(waiting for GPS)',
          );
        }
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
      if (kDebugMode) {
        debugPrint(
          'FieldSessionCoordinator: ensure reason=$reason '
          'accepted=${response.accepted}; missing=${response.missing}',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'FieldSessionCoordinator ensure failed reason=$reason: $error',
        );
      }
    } finally {
      _ensureInFlight = false;
    }
  }

  final Distance _distance = const Distance();

  @override
  void dispose() {
    _catalogModeController?.removeListener(_catalogListener ?? () {});
    _locationService?.removeListener(_locationListener ?? () {});
    _siteService.dispose();
    super.dispose();
  }
}
