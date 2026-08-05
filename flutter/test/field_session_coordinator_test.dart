import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/controllers/field_session_coordinator.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/services/site_service.dart';
import 'package:mesozoica/utils/survey_grid.dart';

import 'helpers/game_config_test_helpers.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService([this._location]);

  LatLng? _location;

  /// Optional delay inside [setFieldSession] to simulate slow GPS reconcile.
  Future<void> Function()? setFieldSessionDelay;

  @override
  LatLng? get currentLocation => _location;

  void setLocation(LatLng location) {
    _location = location;
    notifyListeners();
  }

  void clearLocation() {
    _location = null;
    notifyListeners();
  }

  @override
  Future<void> setFieldSession({
    required bool active,
  }) async {
    final delay = setFieldSessionDelay;
    if (delay != null) {
      await delay();
    }
    lastFieldSessionActive = active;
    notifyListeners();
  }

  bool? lastFieldSessionActive;
  bool _backgroundExploring = false;

  @override
  bool get isBackgroundExploring => _backgroundExploring;

  void setBackgroundExploringFlag(bool value) {
    _backgroundExploring = value;
    notifyListeners();
  }

  @override
  Future<void> onAppResumed() async {
    resumedCalls++;
  }

  @override
  Future<void> onAppBackgrounded() async {
    backgroundedCalls++;
  }

  int resumedCalls = 0;
  int backgroundedCalls = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await loadGameConfigForTest();
  });

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
    expect(locationService.lastFieldSessionActive, isTrue);

    coordinator.dispose();
  });

  test('ensures on foreground and on entering a new 500m cell', () async {
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

    final cellSize = GameConfig.instance.siteGeneration.cellSizeM;
    final start = const LatLng(51.0, 4.0);
    final (ix, iy) = cellIndices(
      start.latitude,
      start.longitude,
      cellSizeM: cellSize,
    );
    final sameCell = cellCenterLatLon(ix, iy, cellSizeM: cellSize);
    final nextCell = cellCenterLatLon(ix + 1, iy, cellSizeM: cellSize);

    final locationService = _FakeLocationService(start);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(bodies.length, 1);
    expect(bodies.single['reason'], FieldSessionCoordinator.reasonResume);

    coordinator.onForeground();
    await pumpUntilIdle();
    expect(bodies.length, 2);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonResume);

    // Same density square — no new ensure.
    locationService.setLocation(LatLng(sameCell.$1, sameCell.$2));
    await pumpUntilIdle();
    expect(bodies.length, 2);

    // New 500 m square — ensure.
    locationService.setLocation(LatLng(nextCell.$1, nextCell.$2));
    await pumpUntilIdle();
    expect(bodies.length, 3);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonMove500m);

    coordinator.dispose();
  });

  test('background lifecycle notifies LocationService via onAppBackgrounded',
      () async {
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
    expect(locationService.backgroundedCalls, 0);

    coordinator.onBackground();
    await pumpUntilIdle();
    expect(locationService.backgroundedCalls, 1);
    expect(coordinator.isSessionActive, isTrue);

    coordinator.dispose();
  });

  test('background exploring still ensures on new 500m cell', () async {
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

    final cellSize = GameConfig.instance.siteGeneration.cellSizeM;
    final start = const LatLng(51.0, 4.0);
    final (ix, iy) = cellIndices(
      start.latitude,
      start.longitude,
      cellSizeM: cellSize,
    );
    final nextCell = cellCenterLatLon(ix + 1, iy, cellSizeM: cellSize);

    final locationService = _FakeLocationService(start)
      ..setBackgroundExploringFlag(true);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(bodies.length, 1);

    coordinator.onBackground();
    await pumpUntilIdle();

    locationService.setLocation(LatLng(nextCell.$1, nextCell.$2));
    await pumpUntilIdle();
    expect(bodies.length, 2);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonMove500m);

    coordinator.dispose();
  });

  test('without background exploring, paused app ignores cell moves', () async {
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

    final cellSize = GameConfig.instance.siteGeneration.cellSizeM;
    final start = const LatLng(51.0, 4.0);
    final (ix, iy) = cellIndices(
      start.latitude,
      start.longitude,
      cellSizeM: cellSize,
    );
    final nextCell = cellCenterLatLon(ix + 1, iy, cellSizeM: cellSize);

    final locationService = _FakeLocationService(start);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(bodies.length, 1);

    coordinator.onBackground();
    await pumpUntilIdle();

    locationService.setLocation(LatLng(nextCell.$1, nextCell.$2));
    await pumpUntilIdle();
    expect(bodies.length, 1);

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

  test('scanAt ensures map-chosen location with scan reason', () async {
    final bodies = <Map<String, dynamic>>[];
    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 12,
              'missing': 88,
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

    await coordinator.scanAt(const LatLng(52.5, 5.5));
    await pumpUntilIdle();

    final scanBody = bodies.firstWhere(
      (body) => body['reason'] == FieldSessionCoordinator.reasonScan,
    );
    expect(scanBody['lat'], 52.5);
    expect(scanBody['lon'], 5.5);
    expect(bodies.where((b) => b['reason'] == FieldSessionCoordinator.reasonScan).length, 1);

    coordinator.dispose();
  });

  test('defers resume ensure when another check is in flight', () async {
    final bodies = <Map<String, dynamic>>[];
    final completer = Completer<void>();

    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            await completer.future;
          }
          return http.Response(
            jsonEncode({
              'accepted': true,
              'existing_in_radius': 100,
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
    await pumpUntilIdle();
    expect(bodies.length, 1);

    coordinator.onForeground();
    await pumpUntilIdle();
    expect(bodies.length, 1);

    completer.complete();
    await pumpUntilIdle();
    expect(bodies.length, 2);
    expect(bodies.last['reason'], FieldSessionCoordinator.reasonResume);

    coordinator.dispose();
  });

  test('stale background after resume does not stop GPS', () async {
    final syncGate = Completer<void>();
    final locationService = _FakeLocationService(const LatLng(51.0, 4.0))
      ..setFieldSessionDelay = () => syncGate.future;

    final coordinator = FieldSessionCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
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
    // Unblock the initial bind sync so the session can start.
    syncGate.complete();
    await pumpUntilIdle();
    expect(locationService.backgroundedCalls, 0);

    final backgroundGate = Completer<void>();
    locationService.setFieldSessionDelay = () => backgroundGate.future;

    // Simulate paused starting a slow _enterBackground (_syncSession).
    coordinator.onBackground();
    await pumpUntilIdle();
    expect(locationService.backgroundedCalls, 0);

    // Resume wins before the background sync finishes.
    coordinator.onForeground();
    backgroundGate.complete();
    await pumpUntilIdle();

    expect(locationService.backgroundedCalls, 0);
    expect(locationService.resumedCalls, greaterThan(0));
    expect(coordinator.isSessionActive, isTrue);

    coordinator.dispose();
  });
}
