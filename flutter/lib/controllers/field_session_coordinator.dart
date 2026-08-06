import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../utils/survey_grid.dart';

/// Orchestrates field-site ensure calls across app lifecycle.
class FieldSessionCoordinator extends ChangeNotifier {
  FieldSessionCoordinator({SiteService? siteService})
    : _siteService = siteService ?? SiteService();

  /// Density square size; walk ensure fires on entering a new cell.
  static double get ensureCellSizeM =>
      GameConfig.instance.siteGeneration.cellSizeM;
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
  (int, int)? _lastEnsureCell;
  String? _pendingEnsureReason;
  VoidCallback? _locationListener;
  bool _openedEnsureDone = false;

  /// True once a resume/startup ensure POST succeeded this foreground period.
  /// Cleared on each [onForeground] so a late GPS fix can still enqueue.
  bool _resumeEnsurePosted = false;

  /// True while [_runResumeEnsure] owns the startup ensure (blocks the
  /// location listener from double-posting during sync/GPS startup).
  bool _resumeEnsureInProgress = false;

  /// Bumped on each foreground/background transition so a stale async
  /// `_enterBackground` cannot stop GPS after a later resume.
  int _lifecycleEpoch = 0;

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
    // Do not sync/GPS here — that notifies the listener before resume is
    // marked in-progress and double-posts ensure. [onForeground] owns sync.
    if (_lifecycle == AppLifecycleState.resumed) {
      onForeground();
    } else {
      await _syncSession();
    }
  }

  Future<void> _runResumeEnsure(int epoch) async {
    if (epoch != _lifecycleEpoch) return;
    _resumeEnsureInProgress = true;
    try {
      await _syncSession();
      if (epoch != _lifecycleEpoch) return;
      await _locationService?.onAppResumed();
      if (epoch != _lifecycleEpoch) return;
      await _maybeEnsure(force: true, reason: reasonResume);
    } finally {
      _resumeEnsureInProgress = false;
      if (epoch == _lifecycleEpoch) {
        _openedEnsureDone = true;
      }
    }
  }

  void _onLocationChanged(LocationService locationService) {
    if (!_sessionActive) return;
    final allowBackground =
        locationService.isBackgroundExploring &&
        _lifecycle != AppLifecycleState.detached;
    if (_lifecycle != AppLifecycleState.resumed && !allowBackground) return;

    final location = locationService.currentLocation;
    final pending = _pendingEnsureReason;
    if (pending != null && location != null) {
      _pendingEnsureReason = null;
      unawaited(_maybeEnsure(force: true, reason: pending));
      return;
    }

    if (location == null) return;

    // Startup ensure never posted (epoch abort, or GPS arrived after defer)
    // and no resume is currently driving it — force enqueue now.
    if (!_resumeEnsurePosted && !_resumeEnsureInProgress) {
      unawaited(_maybeEnsure(force: true, reason: reasonResume));
      return;
    }

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
    _resumeEnsurePosted = false;
    final epoch = ++_lifecycleEpoch;
    unawaited(_runResumeEnsure(epoch));
  }

  void onBackground() {
    if (_lifecycle == AppLifecycleState.detached) {
      return;
    }
    _lifecycle = AppLifecycleState.paused;
    final epoch = ++_lifecycleEpoch;
    // Switch to background GPS profile when exploring is on; otherwise stop.
    unawaited(_enterBackground(epoch));
  }

  Future<void> _enterBackground(int epoch) async {
    await _syncSession();
    // A newer resume/background superseded this transition.
    if (epoch != _lifecycleEpoch) return;
    if (_lifecycle == AppLifecycleState.resumed) return;
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
    // Field GPS on every tab while the app is open; continues in background
    // when the user opts into Explore in background.
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
    final cell = cellIndices(
      location.latitude,
      location.longitude,
      cellSizeM: ensureCellSizeM,
    );
    if (!force && _lastEnsureCell != null && _lastEnsureCell == cell) {
      return null;
    }

    _ensureInFlight = true;

    try {
      final response = await _siteService.requestFieldSiteEnsure(
        lat: location.latitude,
        lon: location.longitude,
        radiusKm: nearbyRadiusKm,
        reason: reason,
      );
      // Only advance the cell throttle on success so a failed/timeout request
      // can retry on the next GPS tick once the cell is still new.
      if (reason != reasonScan) {
        _lastEnsureCell = cell;
      }
      if (reason == reasonResume) {
        _resumeEnsurePosted = true;
      }
      _logEnsure(
        'enqueued reason=$reason accepted=${response.accepted} '
        'cell=${cell.$1}:${cell.$2}',
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
