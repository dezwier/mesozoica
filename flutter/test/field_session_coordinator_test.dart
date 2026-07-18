import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/controllers/field_session_coordinator.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/services/site_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('does not ensure when archive mode is active', () async {
    var ensureCalls = 0;
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();

    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          ensureCalls++;
          return http.Response('', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0, 4.0));
    coordinator.bind(
      catalogModeController: catalogMode,
      locationService: locationService,
    );
    coordinator.onForeground();
    await pumpUntilIdle();

    expect(ensureCalls, 0);
    expect(coordinator.isSessionActive, isFalse);

    coordinator.dispose();
  });

  test('ensures on foreground and throttles movement in field mode', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          requests.add(request.url);
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
    coordinator.bind(
      catalogModeController: catalogMode,
      locationService: locationService,
    );
    coordinator.onForeground();
    await pumpUntilIdle();
    expect(requests.length, 1);

    locationService.setLocation(const LatLng(51.001, 4.0));
    await pumpUntilIdle();
    expect(requests.length, 1);

    locationService.setLocation(const LatLng(51.01, 4.0));
    await pumpUntilIdle();
    expect(requests.length, 2);

    coordinator.dispose();
  });

  test('stop clears active session on detached lifecycle', () async {
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

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
    coordinator.bind(
      catalogModeController: catalogMode,
      locationService: locationService,
    );
    coordinator.onForeground();
    await pumpUntilIdle();
    expect(coordinator.isSessionActive, isTrue);

    coordinator.onLifecycle(AppLifecycleState.detached);
    expect(coordinator.isSessionActive, isFalse);

    coordinator.dispose();
  });
}
