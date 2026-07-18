import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

  LatLng? get currentLocation => _currentLocation;
  double get headingDeg => _headingDeg;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _currentLocation != null;
  bool get isTracking =>
      _mapForeground || (_fieldSession && _locationSub != null);

  Future<void> setMapForeground(bool active) async {
    _mapForeground = active;
    await _reconcileTracking();
  }

  Future<void> setFieldSession({
    required bool active,
    bool backgroundPreferred = false,
  }) async {
    _fieldSession = active;
    _backgroundPreferred = backgroundPreferred;
    if (active && backgroundPreferred) {
      await _ensureBackgroundPermission();
    }
    await _reconcileTracking();
  }

  Future<void> onAppResumed() async {
    if (!_mapForeground && !_fieldSession) return;
    await _startLocationStream(forceRestart: true);
  }

  Future<void> _reconcileTracking() async {
    if (!_mapForeground && !_fieldSession) {
      _stopStreams();
      return;
    }
    if (_mapForeground && !_backgroundPreferred) {
      _startHeading();
    } else {
      _headingSub?.cancel();
      _headingSub = null;
    }
    await _startLocationStream(forceRestart: false);
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
      _error = 'Background location requires Always permission.';
      return false;
    }

    _error = null;
    return true;
  }

  Future<void> _ensureBackgroundPermission() async {
    await _ensurePermission(backgroundPreferred: true);
  }

  LocationSettings _locationSettings({required bool backgroundPreferred}) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: backgroundPreferred
            ? LocationAccuracy.medium
            : LocationAccuracy.best,
        distanceFilter: 5,
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
            ? LocationAccuracy.medium
            : LocationAccuracy.best,
        distanceFilter: 5,
        allowBackgroundLocationUpdates: backgroundPreferred,
        showBackgroundLocationIndicator: backgroundPreferred,
        activityType: ActivityType.fitness,
      );
    }

    return LocationSettings(
      accuracy: backgroundPreferred
          ? LocationAccuracy.medium
          : LocationAccuracy.best,
      distanceFilter: 5,
    );
  }

  Future<void> _startLocationStream({required bool forceRestart}) async {
    if (_locationSub != null && !forceRestart) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final backgroundPreferred = _backgroundPreferred;
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
