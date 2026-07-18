import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/field_session_coordinator.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/services/site_service.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this._location);

  LatLng? _location;

  @override
  LatLng? get currentLocation => _location;

  void setLocation(LatLng location) {
    _location = location;
    notifyListeners();
  }

  @override
  Future<void> setFieldSession({
    required bool active,
    bool backgroundPreferred = false,
  }) async {
    notifyListeners();
  }

  @override
  Future<void> onAppResumed() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('ensures on app open in archive mode', () async {
    var ensureCalls = 0;
    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          ensureCalls++;
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 0,
              'missing': 100,
              'radius_km': 1.0,
            }),
            202,
          );
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0, 4.0));
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();

    expect(ensureCalls, 1);
    expect(coordinator.isSessionActive, isTrue);

    coordinator.dispose();
  });

  test('ensures on foreground and throttles movement', () async {
    final bodies = <Map<String, dynamic>>[];
    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 0,
              'missing': 100,
              'radius_km': 1.0,
            }),
            202,
          );
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0, 4.0));
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(bodies.length, 1);
    expect(bodies.single['reason'], FieldSessionCoordinator.reasonResume);

    coordinator.onForeground();
    await pumpUntilIdle();
    expect(bodies.length, 2);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonResume);

    locationService.setLocation(const LatLng(51.001, 4.0));
    await pumpUntilIdle();
    expect(bodies.length, 2);

    locationService.setLocation(const LatLng(51.01, 4.0));
    await pumpUntilIdle();
    expect(bodies.length, 3);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonMove500m);

    coordinator.dispose();
  });

  test('stop clears active session on detached lifecycle', () async {
    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 0,
              'missing': 0,
              'radius_km': 1.0,
            }),
            202,
          );
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0, 4.0));
    coordinator.bind(locationService: locationService);
    coordinator.onForeground();
    await pumpUntilIdle();
    expect(coordinator.isSessionActive, isTrue);

    coordinator.onLifecycle(AppLifecycleState.detached);
    expect(coordinator.isSessionActive, isFalse);

    coordinator.dispose();
  });

  test('defers resume ensure until first GPS fix', () async {
    final bodies = <Map<String, dynamic>>[];
    final locationService = _FakeLocationService(null);

    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 0,
              'missing': 100,
              'radius_km': 1.0,
            }),
            202,
          );
        }),
      ),
    );

    coordinator.bind(locationService: locationService);
    coordinator.onForeground();
    await pumpUntilIdle();
    expect(bodies, isEmpty);

    locationService.setLocation(const LatLng(51.0, 4.0));
    await pumpUntilIdle();
    expect(bodies.length, 1);
    expect(bodies.single['reason'], FieldSessionCoordinator.reasonResume);

    coordinator.dispose();
  });
}
