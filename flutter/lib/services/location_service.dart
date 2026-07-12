import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Foreground-only user location for the map tab.
class LocationService extends ChangeNotifier {
  LatLng? _currentLocation;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Position>? _locationSub;
  bool _isActive = false;

  LatLng? get currentLocation => _currentLocation;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLocation => _currentLocation != null;
  bool get isActive => _isActive;

  Future<void> start() async {
    if (_isActive) return;
    _isActive = true;
    await _initialize();
  }

  void stop() {
    if (!_isActive) return;
    _isActive = false;
    _locationSub?.cancel();
    _locationSub = null;
  }

  Future<void> _initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _error = 'Location services are disabled.';
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _error = 'Location permission denied.';
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _error = 'Location permission permanently denied.';
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      _currentLocation = LatLng(position.latitude, position.longitude);

      _locationSub?.cancel();
      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
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
        debugPrint('LocationService.initialize failed: $error');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
