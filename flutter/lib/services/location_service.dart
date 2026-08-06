import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GPS precision / battery profile for the active stream.
enum GpsProfile {
  /// Map tab foreground — tight follow for map fluency.
  high,

  /// App open, not on map — discovery / field ensure.
  fieldForeground,

  /// Background exploring while moving (or recently moved).
  fieldBackground,

  /// Background exploring while stationary — sparse updates.
  idleBackground,
}

/// Whether GPS should be actively streaming.
@visibleForTesting
bool shouldTrackLocation({
  required bool wantsLocation,
  required bool appForeground,
  required bool backgroundExploring,
}) {
  return wantsLocation && (appForeground || backgroundExploring);
}

/// Resolve which GPS profile to use for the current UI / motion state.
@visibleForTesting
GpsProfile resolveGpsProfile({
  required bool mapForeground,
  required bool appForeground,
  required bool backgroundExploring,
  required bool stationary,
}) {
  if (mapForeground && appForeground) return GpsProfile.high;
  if (appForeground) return GpsProfile.fieldForeground;
  if (backgroundExploring) {
    return stationary ? GpsProfile.idleBackground : GpsProfile.fieldBackground;
  }
  return GpsProfile.fieldForeground;
}

/// User location for the map tab and field-session ensure tracking.
class LocationService extends ChangeNotifier {
  static const prefsKeyBackgroundExploring = 'background_exploring';
  static const _stationarySpeedMps = 0.5;
  static const _stationaryAfter = Duration(seconds: 60);

  LatLng? _currentLocation;
  Position? _lastPosition;
  DateTime? _lastPositionAt;
  DateTime? _lastSignificantMoveAt;
  double _headingDeg = 0;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double>? _headingSub;
  Timer? _headingNotifyTimer;
  Timer? _stationaryCheckTimer;
  bool _mapForeground = false;
  bool _fieldSession = false;
  bool _appForeground = true;
  bool _backgroundExploring = false;
  bool _prefsLoaded = false;
  GpsProfile _activeProfile = GpsProfile.fieldForeground;

  /// FlutterCompass only when rotate mode or guidance needle needs heading.
  bool _headingWanted = false;

  /// Heading updates without [notifyListeners] (avoids ~60 Hz map rebuilds).
  final ValueNotifier<double> headingListenable = ValueNotifier<double>(0);

  /// GPS fixes without forcing map-screen rebuilds — map listens directly.
  final ValueNotifier<LatLng?> locationListenable = ValueNotifier<LatLng?>(
    null,
  );

  // Perf HUD counters (monotonic; HUD diffs over a window).
  int _gpsUpdateCount = 0;
  int _headingNotifyCount = 0;
  int _headingSampleCount = 0;

  LatLng? get currentLocation => _currentLocation;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastPositionAt => _lastPositionAt;
  bool get isAppForeground => _appForeground;
  double get headingDeg => _headingDeg;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _currentLocation != null;
  bool get isMapForeground => _mapForeground;
  bool get isFieldSession => _fieldSession;
  bool get isBackgroundExploring => _backgroundExploring;
  bool get isGpsStreamActive => _locationSub != null;
  bool get isHeadingStreamActive => _headingSub != null;
  bool get isHighPrecisionGps => _activeProfile == GpsProfile.high;
  GpsProfile get activeProfile => _activeProfile;
  bool get isTracking =>
      _mapForeground || (_fieldSession && _locationSub != null);

  int get gpsUpdateCount => _gpsUpdateCount;
  int get headingNotifyCount => _headingNotifyCount;
  int get headingSampleCount => _headingSampleCount;

  /// True when a GPS stream should be running.
  @visibleForTesting
  bool get isLocationStreamDesired => shouldTrackLocation(
    wantsLocation: _mapForeground || _fieldSession,
    appForeground: _appForeground,
    backgroundExploring: _backgroundExploring,
  );

  /// Age of the last GPS fix, or null if never fixed.
  Duration? get gpsFixAge {
    final at = _lastPositionAt;
    if (at == null) return null;
    return DateTime.now().difference(at);
  }

  bool get isStationary {
    final movedAt = _lastSignificantMoveAt;
    if (movedAt == null) return false;
    return DateTime.now().difference(movedAt) >= _stationaryAfter;
  }

  /// Load persisted background-exploring preference (call once at startup).
  Future<void> loadPreferences() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _backgroundExploring =
          prefs.getBool(prefsKeyBackgroundExploring) ?? false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('LocationService.loadPreferences: $error');
      }
    }
  }

  /// Opt in/out of background field GPS. Requests Always permission when
  /// enabling. Returns whether background exploring is now on.
  Future<bool> setBackgroundExploring(bool enabled) async {
    await loadPreferences();
    if (enabled == _backgroundExploring) return _backgroundExploring;

    if (enabled) {
      final permitted = await _ensureAlwaysPermission();
      if (!permitted) {
        _error ??=
            'Always location permission is required for background '
            'exploring.';
        notifyListeners();
        return false;
      }
    }

    _backgroundExploring = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKeyBackgroundExploring, enabled);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('LocationService.setBackgroundExploring persist: $error');
      }
    }
    notifyListeners();
    await _reconcileTracking(forceRestartLocation: true);
    return _backgroundExploring;
  }

  Future<void> setMapForeground(bool active) async {
    final changed = _mapForeground != active;
    _mapForeground = active;
    if (!changed) return;
    // Map tab only controls the compass; discovery GPS stays on for all tabs
    // via the field session. Precision profile may change → restart GPS.
    await _reconcileTracking(forceRestartLocation: true);
  }

  /// Enable FlutterCompass while rotate mode or guidance needle needs heading.
  Future<void> setHeadingWanted(bool wanted) async {
    if (_headingWanted == wanted) return;
    _headingWanted = wanted;
    await _reconcileHeadingOnly();
  }

  Future<void> setFieldSession({required bool active}) async {
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

  /// Switch to background profile (or stop) when the app is backgrounded.
  ///
  /// When [isBackgroundExploring] is on, GPS keeps running with a relaxed
  /// profile so discovery / walk XP / exploration continue while locked.
  Future<void> onAppBackgrounded() async {
    if (!_appForeground) return;
    _appForeground = false;
    await _reconcileTracking(forceRestartLocation: true);
  }

  Future<void> _reconcileTracking({bool forceRestartLocation = false}) async {
    final wantsLocation = _mapForeground || _fieldSession;
    if (!shouldTrackLocation(
      wantsLocation: wantsLocation,
      appForeground: _appForeground,
      backgroundExploring: _backgroundExploring,
    )) {
      _stopStreams();
      _activeProfile = GpsProfile.fieldForeground;
      _stationaryCheckTimer?.cancel();
      _stationaryCheckTimer = null;
      return;
    }
    _reconcileHeadingStream();
    _scheduleStationaryCheck();
    final wantProfile = resolveGpsProfile(
      mapForeground: _mapForeground,
      appForeground: _appForeground,
      backgroundExploring: _backgroundExploring,
      stationary: isStationary,
    );
    final profileChanged = wantProfile != _activeProfile;
    await _startLocationStream(
      forceRestart: forceRestartLocation || profileChanged,
      profile: wantProfile,
    );
  }

  void _scheduleStationaryCheck() {
    if (!_backgroundExploring || _appForeground) {
      _stationaryCheckTimer?.cancel();
      _stationaryCheckTimer = null;
      return;
    }
    _stationaryCheckTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_backgroundExploring || _appForeground) return;
      final want = resolveGpsProfile(
        mapForeground: _mapForeground,
        appForeground: _appForeground,
        backgroundExploring: _backgroundExploring,
        stationary: isStationary,
      );
      if (want != _activeProfile) {
        unawaited(_reconcileTracking(forceRestartLocation: true));
      }
    });
  }

  Future<void> _reconcileHeadingOnly() async {
    if (!_mapForeground || !_appForeground) {
      _stopHeadingStream();
      return;
    }
    _reconcileHeadingStream();
  }

  void _reconcileHeadingStream() {
    // Compass is foreground-only UI for rotate / guidance needle — not all
    // map-tab time (north-fixed FollowPuck uses native Mapbox heading).
    if (_mapForeground && _appForeground && _headingWanted) {
      _startHeading();
    } else {
      _stopHeadingStream();
    }
  }

  void _stopHeadingStream() {
    _headingSub?.cancel();
    _headingSub = null;
    _headingNotifyTimer?.cancel();
    _headingNotifyTimer = null;
  }

  void _stopStreams() {
    _locationSub?.cancel();
    _locationSub = null;
    _stopHeadingStream();
  }

  void _startHeading() {
    if (_headingSub != null) return;
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
            _headingSampleCount++;
            _headingDeg = heading;
            // Coalesce compass spam to ~60 Hz for listeners that opt in.
            _headingNotifyTimer ??= Timer(const Duration(milliseconds: 16), () {
              _headingNotifyTimer = null;
              _headingNotifyCount++;
              headingListenable.value = _headingDeg;
              // Do NOT call notifyListeners() — heading must not rebuild the map.
            });
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

  /// Upgrade from When-In-Use to Always for background exploring.
  Future<bool> _ensureAlwaysPermission() async {
    final whileInUseOk = await _ensurePermission();
    if (!whileInUseOk) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      _error = null;
      return true;
    }

    // Second prompt (iOS) / background location step (Android 10+).
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.always) {
      _error = null;
      return true;
    }

    _error =
        'Always location permission is required for background exploring. '
        'You can enable it in system Settings.';
    return false;
  }

  LocationSettings _locationSettings({required GpsProfile profile}) {
    final (accuracy, distanceFilter, interval) = switch (profile) {
      GpsProfile.high => (LocationAccuracy.high, 5, const Duration(seconds: 1)),
      GpsProfile.fieldForeground => (
        LocationAccuracy.medium,
        10,
        const Duration(seconds: 2),
      ),
      GpsProfile.fieldBackground => (
        LocationAccuracy.medium,
        15,
        const Duration(seconds: 5),
      ),
      GpsProfile.idleBackground => (
        LocationAccuracy.low,
        75,
        const Duration(seconds: 30),
      ),
    };

    final allowBackground = _backgroundExploring && !_appForeground;

    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
        foregroundNotificationConfig: _backgroundExploring
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Exploring fossil sites',
                notificationText:
                    'Mesozoica is tracking your location for discoveries '
                    'and walk XP. Turn off in Settings to stop.',
                notificationChannelName: 'Field exploring',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }

    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        allowBackgroundLocationUpdates: allowBackground || _backgroundExploring,
        showBackgroundLocationIndicator: _backgroundExploring,
        pauseLocationUpdatesAutomatically: profile == GpsProfile.idleBackground,
        activityType: ActivityType.fitness,
      );
    }

    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }

  Future<void> _startLocationStream({
    required bool forceRestart,
    required GpsProfile profile,
  }) async {
    if (_locationSub != null && !forceRestart && _activeProfile == profile) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final permitted = await _ensurePermission();
      if (!permitted) {
        return;
      }
      if (_backgroundExploring) {
        final alwaysOk = await _ensureAlwaysPermission();
        if (!alwaysOk && !_appForeground) {
          // Can't run background without Always — fall back to stopped.
          _stopStreams();
          return;
        }
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _applyPosition(lastKnown);
      }

      _activeProfile = profile;
      final settings = _locationSettings(profile: profile);
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      _applyPosition(position);

      _locationSub?.cancel();
      _locationSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
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
    final previous = _currentLocation;
    _lastPosition = position;
    _lastPositionAt = DateTime.now();
    _currentLocation = LatLng(position.latitude, position.longitude);
    _gpsUpdateCount++;

    final speed = position.speed;
    final movingBySpeed = speed.isFinite && speed >= _stationarySpeedMps;
    var movedMeters = 0.0;
    if (previous != null) {
      movedMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
    }
    if (movingBySpeed || movedMeters >= 5) {
      _lastSignificantMoveAt = DateTime.now();
    } else {
      _lastSignificantMoveAt ??= DateTime.now();
    }

    locationListenable.value = _currentLocation;
    notifyListeners();
  }

  @override
  void dispose() {
    _stationaryCheckTimer?.cancel();
    _stopStreams();
    headingListenable.dispose();
    locationListenable.dispose();
    super.dispose();
  }
}
