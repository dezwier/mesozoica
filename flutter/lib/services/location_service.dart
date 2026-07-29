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
  DateTime? _lastPositionAt;
  double _headingDeg = 0;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<double>? _headingSub;
  Timer? _headingNotifyTimer;
  bool _mapForeground = false;
  bool _fieldSession = false;
  bool _appForeground = true;
  bool _highPrecisionGps = false;
  /// FlutterCompass only when rotate mode or guidance needle needs heading.
  bool _headingWanted = false;

  /// Heading updates without [notifyListeners] (avoids ~60 Hz map rebuilds).
  final ValueNotifier<double> headingListenable = ValueNotifier<double>(0);

  /// GPS fixes without forcing map-screen rebuilds — map listens directly.
  final ValueNotifier<LatLng?> locationListenable = ValueNotifier<LatLng?>(null);

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
  bool get isGpsStreamActive => _locationSub != null;
  bool get isHeadingStreamActive => _headingSub != null;
  bool get isHighPrecisionGps => _highPrecisionGps;
  bool get isTracking =>
      _mapForeground || (_fieldSession && _locationSub != null);

  int get gpsUpdateCount => _gpsUpdateCount;
  int get headingNotifyCount => _headingNotifyCount;
  int get headingSampleCount => _headingSampleCount;

  /// True when a foreground GPS stream should be running.
  @visibleForTesting
  bool get isLocationStreamDesired => shouldTrackLocation(
        wantsLocation: _mapForeground || _fieldSession,
        appForeground: _appForeground,
      );

  /// Age of the last GPS fix, or null if never fixed.
  Duration? get gpsFixAge {
    final at = _lastPositionAt;
    if (at == null) return null;
    return DateTime.now().difference(at);
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
      _highPrecisionGps = false;
      return;
    }
    _reconcileHeadingStream();
    final wantHigh = _mapForeground;
    final profileChanged = wantHigh != _highPrecisionGps;
    await _startLocationStream(
      forceRestart: forceRestartLocation || profileChanged,
    );
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
        _headingNotifyTimer ??= Timer(
          const Duration(milliseconds: 16),
          () {
            _headingNotifyTimer = null;
            _headingNotifyCount++;
            headingListenable.value = _headingDeg;
            // Do NOT call notifyListeners() — heading must not rebuild the map.
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

  /// Tighter GPS on the map tab; relaxed while only the field session needs it.
  LocationSettings _locationSettings({required bool highPrecision}) {
    final accuracy =
        highPrecision ? LocationAccuracy.high : LocationAccuracy.medium;
    final distanceFilter = highPrecision ? 5 : 10;
    final interval = highPrecision
        ? const Duration(seconds: 1)
        : const Duration(seconds: 2);

    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
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

    return LocationSettings(
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

      final highPrecision = _mapForeground;
      _highPrecisionGps = highPrecision;
      final settings = _locationSettings(highPrecision: highPrecision);
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
    _lastPositionAt = DateTime.now();
    _currentLocation = LatLng(position.latitude, position.longitude);
    _gpsUpdateCount++;
    locationListenable.value = _currentLocation;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStreams();
    headingListenable.dispose();
    locationListenable.dispose();
    super.dispose();
  }
}
