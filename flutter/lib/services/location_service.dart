import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Whether GPS should be actively streaming.
///
/// Location is While-In-Use only (Pokémon GO style): no background GPS when
/// the app is paused/locked. Discovery and map follow resume on foreground.
@visibleForTesting
bool shouldTrackLocation({
  required bool wantsLocation,
  required bool appForeground,
}) {
  return wantsLocation && appForeground;
}

/// User location for the map tab and field-session ensure tracking.
class LocationService extends ChangeNotifier {
  LatLng? _currentLocation;
  Position? _lastPosition;
  double _headingDeg = 0;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double>? _headingSub;
  Timer? _headingNotifyTimer;
  bool _mapForeground = false;
  bool _fieldSession = false;
  bool _appForeground = true;

  LatLng? get currentLocation => _currentLocation;
  Position? get lastPosition => _lastPosition;
  bool get isAppForeground => _appForeground;
  double get headingDeg => _headingDeg;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _currentLocation != null;
  bool get isTracking =>
      _mapForeground || (_fieldSession && _locationSub != null);

  /// True when a foreground GPS stream should be running.
  @visibleForTesting
  bool get isLocationStreamDesired => shouldTrackLocation(
        wantsLocation: _mapForeground || _fieldSession,
        appForeground: _appForeground,
      );

  Future<void> setMapForeground(bool active) async {
    final changed = _mapForeground != active;
    _mapForeground = active;
    if (!changed) return;
    // Map tab only controls the compass; discovery GPS stays on for all tabs
    // via the field session and must not restart on tab switches.
    await _reconcileTracking(forceRestartLocation: false);
  }

  Future<void> setFieldSession({
    required bool active,
    @Deprecated('Background GPS is no longer supported')
    bool backgroundPreferred = false,
  }) async {
    final settingsChanged = _fieldSession != active;
    _fieldSession = active;
    await _reconcileTracking(forceRestartLocation: settingsChanged);
  }

  Future<void> onAppResumed() async {
    final wasBackground = !_appForeground;
    _appForeground = true;
    if (!_mapForeground && !_fieldSession) return;
    await _reconcileTracking(forceRestartLocation: wasBackground);
  }

  /// Stop GPS while the app is backgrounded or locked.
  ///
  /// Walked distance continues via HealthKit / Health Connect; proximity
  /// discovery resumes when the app returns to the foreground.
  Future<void> onAppBackgrounded() async {
    if (!_appForeground) return;
    _appForeground = false;
    await _reconcileTracking(forceRestartLocation: true);
  }

  Future<void> _reconcileTracking({bool forceRestartLocation = false}) async {
    final wantsLocation = _mapForeground || _fieldSession;
    if (!wantsLocation || !_appForeground) {
      _stopStreams();
      return;
    }
    // Compass is foreground-only UI for the map tab.
    if (_mapForeground) {
      _startHeading();
    } else {
      _headingSub?.cancel();
      _headingSub = null;
      _headingNotifyTimer?.cancel();
      _headingNotifyTimer = null;
    }
    await _startLocationStream(forceRestart: forceRestartLocation);
  }

  void _stopStreams() {
    _locationSub?.cancel();
    _locationSub = null;
    _headingSub?.cancel();
    _headingSub = null;
    _headingNotifyTimer?.cancel();
    _headingNotifyTimer = null;
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
        // Coalesce compass spam to ~60 Hz so the map stays smooth.
        _headingNotifyTimer ??= Timer(
          const Duration(milliseconds: 16),
          () {
            _headingNotifyTimer = null;
            notifyListeners();
          },
        );
      },
      onError: (Object error) {
        if (kDebugMode) {
          debugPrint('LocationService heading stream error: $error');
        }
      },
    );
  }

  Future<bool> _ensurePermission() async {
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

    _error = null;
    return true;
  }

  LocationSettings _locationSettings() {
    const accuracy = LocationAccuracy.best;
    const distanceFilter = 1;

    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(milliseconds: 500),
      );
    }

    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.fitness,
      );
    }

    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  Future<void> _startLocationStream({required bool forceRestart}) async {
    if (_locationSub != null && !forceRestart) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final permitted = await _ensurePermission();
      if (!permitted) {
        return;
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _applyPosition(lastKnown);
      }

      final settings = _locationSettings();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      _applyPosition(position);

      _locationSub?.cancel();
      _locationSub = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        _applyPosition,
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

  void _applyPosition(Position position) {
    _lastPosition = position;
    _currentLocation = LatLng(position.latitude, position.longitude);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStreams();
    super.dispose();
  }
}
