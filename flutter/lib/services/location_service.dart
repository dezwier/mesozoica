import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Whether GPS should use the background-capable profile.
///
/// Field sessions prefer background GPS, but while the map is actively shown
/// in the foreground we keep the high-accuracy foreground profile. As soon as
/// the app itself is backgrounded or locked, switch back to background GPS
/// even if the map tab is still selected.
@visibleForTesting
bool shouldUseBackgroundLocationProfile({
  required bool backgroundPreferred,
  required bool mapForeground,
  required bool appForeground,
}) {
  return backgroundPreferred && (!mapForeground || !appForeground);
}

/// User location for the map tab and field-session ensure tracking.
class LocationService extends ChangeNotifier {
  LatLng? _currentLocation;
  double _headingDeg = 0;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double>? _headingSub;
  bool _mapForeground = false;
  bool _fieldSession = false;
  bool _backgroundPreferred = false;
  bool _appForeground = true;

  LatLng? get currentLocation => _currentLocation;
  double get headingDeg => _headingDeg;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _currentLocation != null;
  bool get isTracking =>
      _mapForeground || (_fieldSession && _locationSub != null);

  /// True when GPS uses the background-capable profile (FGS / Always updates).
  @visibleForTesting
  bool get usesBackgroundLocationProfile => _useBackgroundLocationProfile;

  Future<void> setMapForeground(bool active) async {
    final changed = _mapForeground != active;
    _mapForeground = active;
    await _reconcileTracking(forceRestartLocation: changed);
  }

  Future<void> setFieldSession({
    required bool active,
    bool backgroundPreferred = false,
  }) async {
    final settingsChanged =
        _fieldSession != active || _backgroundPreferred != backgroundPreferred;
    _fieldSession = active;
    _backgroundPreferred = backgroundPreferred;
    if (active && backgroundPreferred && _useBackgroundLocationProfile) {
      await _ensureBackgroundPermission();
    }
    await _reconcileTracking(forceRestartLocation: settingsChanged);
  }

  Future<void> onAppResumed() async {
    final wasBackground = !_appForeground;
    _appForeground = true;
    if (!_mapForeground && !_fieldSession) return;
    await _reconcileTracking(forceRestartLocation: wasBackground);
  }

  /// Switch to the background-capable GPS profile while the process stays alive.
  ///
  /// The map tab can still report "foreground" while the app is backgrounded or
  /// the phone is locked; without this restart, iOS keeps
  /// `allowBackgroundLocationUpdates: false` and Android has no FGS, so 50 m
  /// discovery stops.
  Future<void> onAppBackgrounded() async {
    if (!_appForeground) return;
    _appForeground = false;
    if (!_fieldSession || !_backgroundPreferred) return;
    if (_useBackgroundLocationProfile) {
      await _ensureBackgroundPermission();
    }
    await _reconcileTracking(forceRestartLocation: true);
  }

  Future<void> _reconcileTracking({bool forceRestartLocation = false}) async {
    if (!_mapForeground && !_fieldSession) {
      _stopStreams();
      return;
    }
    // Compass is foreground-only UI; keep it while the map tab is active and
    // the app itself is in the foreground.
    if (_mapForeground && _appForeground) {
      _startHeading();
    } else {
      _headingSub?.cancel();
      _headingSub = null;
    }
    await _startLocationStream(forceRestart: forceRestartLocation);
  }

  void _stopStreams() {
    _locationSub?.cancel();
    _locationSub = null;
    _headingSub?.cancel();
    _headingSub = null;
  }

  void _startHeading() {
    _headingSub?.cancel();
    final events = FlutterCompass.events;
    if (events == null) {
      if (kDebugMode) {
        debugPrint('LocationService: compass not available on this device');
      }
      return;
    }

    _headingSub = events
        .where((event) => event.heading != null)
        .map((event) => (event.heading! + 360) % 360)
        .listen(
      (heading) {
        _headingDeg = heading;
        notifyListeners();
      },
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('LocationService heading stream error: $error');
        }
      },
    );
  }

  Future<bool> _ensurePermission({required bool backgroundPreferred}) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _error = 'Location services are disabled.';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _error = 'Location permission denied.';
      return false;
    }

    if (backgroundPreferred &&
        permission == LocationPermission.whileInUse &&
        !kIsWeb) {
      permission = await Geolocator.requestPermission();
    }

    if (backgroundPreferred &&
        permission != LocationPermission.always &&
        !kIsWeb &&
        Platform.isIOS) {
      // Keep tracking alive with While In Use; iOS simply will not deliver
      // suspended-state updates until the user grants Always.
      _error = 'Background location requires Always permission.';
    } else {
      _error = null;
    }
    return true;
  }

  Future<void> _ensureBackgroundPermission() async {
    await _ensurePermission(backgroundPreferred: true);
  }

  /// Background profile when field session wants it and either the map is not
  /// showing or the app itself is backgrounded / locked.
  bool get _useBackgroundLocationProfile => shouldUseBackgroundLocationProfile(
        backgroundPreferred: _backgroundPreferred,
        mapForeground: _mapForeground,
        appForeground: _appForeground,
      );

  LocationSettings _locationSettings({required bool backgroundPreferred}) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        // High accuracy keeps 50 m discovery reliable while exploring locked.
        accuracy: backgroundPreferred
            ? LocationAccuracy.high
            : LocationAccuracy.best,
        distanceFilter: backgroundPreferred ? 10 : 5,
        foregroundNotificationConfig: backgroundPreferred
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Field exploration active',
                notificationText:
                    'Mesozoica is updating nearby field sites while you explore.',
                enableWakeLock: true,
              )
            : null,
      );
    }

    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: backgroundPreferred
            ? LocationAccuracy.high
            : LocationAccuracy.best,
        distanceFilter: backgroundPreferred ? 10 : 5,
        allowBackgroundLocationUpdates: backgroundPreferred,
        showBackgroundLocationIndicator: backgroundPreferred,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }

    return LocationSettings(
      accuracy: backgroundPreferred
          ? LocationAccuracy.high
          : LocationAccuracy.best,
      distanceFilter: backgroundPreferred ? 10 : 5,
    );
  }

  Future<void> _startLocationStream({required bool forceRestart}) async {
    if (_locationSub != null && !forceRestart) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final backgroundPreferred = _useBackgroundLocationProfile;
      final permitted = await _ensurePermission(
        backgroundPreferred: backgroundPreferred,
      );
      if (!permitted) {
        return;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
        notifyListeners();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings(
          backgroundPreferred: backgroundPreferred,
        ),
      );
      _currentLocation = LatLng(position.latitude, position.longitude);
      notifyListeners();

      _locationSub?.cancel();
      _locationSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(
          backgroundPreferred: backgroundPreferred,
        ),
      ).listen(
        (position) {
          _currentLocation = LatLng(position.latitude, position.longitude);
          notifyListeners();
        },
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('LocationService stream error: $error');
          }
        },
      );
    } catch (error) {
      _error = 'Could not get your location.';
      if (kDebugMode) {
        debugPrint('LocationService stream start failed: $error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopStreams();
    super.dispose();
  }
}
