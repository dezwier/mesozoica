import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/weather_status.dart';
import '../services/api_client.dart';
import '../services/location_service.dart';
import '../utils/solar_period.dart';

/// Continuous location weather for HUD + weather_time gameplay modifiers.
///
/// - [weatherTime] updates locally via [Solar.periodAt] (~60s / on move).
/// - Type + temperature refresh from backend every [pollInterval] or after
///   [moveRefreshThresholdM] (half of a 5 km weather cell).
class WeatherController extends ChangeNotifier with WidgetsBindingObserver {
  WeatherController({
    required LocationService locationService,
    this.pollInterval = const Duration(minutes: 15),
    this.moveRefreshThresholdM = 2500,
    this.solarTickInterval = const Duration(seconds: 60),
  }) : _location = locationService {
    _location.addListener(_onLocationChanged);
    WidgetsBinding.instance.addObserver(this);
    _solarTimer = Timer.periodic(solarTickInterval, (_) => _refreshSolar());
    _onLocationChanged();
  }

  final LocationService _location;
  final Duration pollInterval;
  final double moveRefreshThresholdM;
  final Duration solarTickInterval;

  WeatherStatus? _status;
  LatLng? _lastFetchAt;
  DateTime? _lastFetchTime;
  bool _fetching = false;
  bool _appForeground = true;
  Timer? _solarTimer;
  String? _error;

  WeatherStatus? get status => _status;

  /// Current solar period name (dawn|day|dusk|golden_hour|night), or null if no GPS yet.
  String? get weatherTime => _status?.weatherTime;

  String? get error => _error;

  void _onLocationChanged() {
    _refreshSolar();
    unawaited(_maybeFetchWeather());
  }

  void _refreshSolar() {
    final loc = _location.currentLocation;
    if (loc == null) return;
    final period = Solar.periodAt(
      latitude: loc.latitude,
      longitude: loc.longitude,
    ).name;
    final current = _status;
    if (current == null) {
      _status = WeatherStatus(
        weatherType: 'unknown',
        temperatureC: 0,
        weatherTime: period,
      );
      notifyListeners();
      return;
    }
    if (current.weatherTime == period) return;
    _status = current.copyWith(weatherTime: period);
    notifyListeners();
  }

  Future<void> _maybeFetchWeather({bool force = false}) async {
    if (!_appForeground || _fetching) return;
    final loc = _location.currentLocation;
    if (loc == null) return;

    final now = DateTime.now();
    if (!force && _lastFetchAt != null && _lastFetchTime != null) {
      final age = now.difference(_lastFetchTime!);
      final movedM = Geolocator.distanceBetween(
        _lastFetchAt!.latitude,
        _lastFetchAt!.longitude,
        loc.latitude,
        loc.longitude,
      );
      if (age < pollInterval && movedM < moveRefreshThresholdM) return;
    }

    _fetching = true;
    try {
      final json = await ApiClient.instance.get(
        '/api/v1/weather',
        query: {
          'lat': loc.latitude.toString(),
          'lon': loc.longitude.toString(),
        },
      );
      final remote = WeatherStatus.fromJson(json);
      // Prefer freshly computed local solar period over the round-trip value.
      final period = Solar.periodAt(
        latitude: loc.latitude,
        longitude: loc.longitude,
      ).name;
      _status = remote.copyWith(weatherTime: period);
      _lastFetchAt = loc;
      _lastFetchTime = now;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      // Keep last known status; still refresh solar.
      _refreshSolar();
    } finally {
      _fetching = false;
    }
  }

  /// Force a weather API refresh (e.g. pull-to-refresh / debug).
  Future<void> refresh() => _maybeFetchWeather(force: true);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    if (_appForeground) {
      _refreshSolar();
      unawaited(_maybeFetchWeather());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _solarTimer?.cancel();
    _location.removeListener(_onLocationChanged);
    super.dispose();
  }
}
