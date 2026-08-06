import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/field_discovery_coordinator.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/services/site_service.dart';

import 'helpers/game_config_test_helpers.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService(this._location, {double? speedMps})
    : _speedMps = speedMps;

  LatLng? _location;
  double? _speedMps;

  @override
  LatLng? get currentLocation => _location;

  @override
  Position? get lastPosition {
    final loc = _location;
    if (loc == null) return null;
    return Position(
      latitude: loc.latitude,
      longitude: loc.longitude,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: _speedMps ?? -1,
      speedAccuracy: 0,
    );
  }

  void setLocation(LatLng location, {double? speedMps}) {
    _location = location;
    if (speedMps != null) _speedMps = speedMps;
    notifyListeners();
  }

  void setSpeedMps(double? speedMps) {
    _speedMps = speedMps;
    notifyListeners();
  }

  @override
  Future<void> setFieldSession({required bool active}) async {
    notifyListeners();
  }

  @override
  Future<void> onAppResumed() async {}

  @override
  Future<void> onAppBackgrounded() async {}
}

Map<String, dynamic> _siteJson({
  required int siteId,
  required double lat,
  required double lon,
  String status = 'hidden',
}) {
  return {
    'site_id': siteId,
    'latitude': lat,
    'longitude': lon,
    'formation': 'Test Site $siteId',
    'data_source': 'field',
    'status': status,
  };
}

Map<String, dynamic> _discoverResponseJson({
  required int siteId,
  required double lat,
  required double lon,
}) {
  return {
    'site': _siteJson(siteId: siteId, lat: lat, lon: lon, status: 'discovered'),
    'status': 'done',
    'onboarded': true,
    'generated': false,
    'fossils_ready': true,
    'surface_fossils': <dynamic>[],
  };
}

http.Response _chanceMissResponse() {
  return http.Response(
    jsonEncode({
      'detail':
          'Discovery chance miss - stay nearby or re-enter range to try again',
      'type': 'DiscoveryChanceMissError',
    }),
    400,
  );
}

/// ~200 m south of (51.0, 4.0) — outside the 20 m discover radius.
const _outside = LatLng(50.9982, 4.0000);

/// ~11 m from (51.0, 4.0) — inside the discover radius.
const _inside = LatLng(51.0001, 4.0000);

/// Longer than [pumpUntilIdle] so the dwell timer does not fire mid-setup.
const _shortReroll = Duration(milliseconds: 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  setUp(() async {
    await loadGameConfigForTest();
  });

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  test(
    'does not discover immediately when opening already inside radius',
    () async {
      final discoverCalls = <int>[];
      final coordinator = FieldDiscoveryCoordinator(
        discoveryRerollIntervalOverride: const Duration(seconds: 60),
        siteService: SiteService(
          client: MockClient((request) async {
            if (request.url.path.contains('nearby-discoverable')) {
              return http.Response(
                jsonEncode({
                  'items': [_siteJson(siteId: 1, lat: 51.0000, lon: 4.0000)],
                  'total': 1,
                  'generated': 0,
                  'radius_km': 1.0,
                }),
                200,
              );
            }
            if (request.method == 'POST' &&
                request.url.path.contains('/discover')) {
              discoverCalls.add(int.parse(request.url.pathSegments[3]));
              return http.Response(
                jsonEncode(
                  _discoverResponseJson(siteId: 1, lat: 51.0, lon: 4.0),
                ),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      );

      final locationService = _FakeLocationService(_inside);
      coordinator.bind(locationService: locationService);
      await pumpUntilIdle();

      expect(discoverCalls, isEmpty);
      expect(coordinator.pendingCelebration, isNull);

      // Small move still inside — still not an immediate free roll.
      locationService.setLocation(const LatLng(51.00005, 4.0000));
      await pumpUntilIdle();
      expect(discoverCalls, isEmpty);

      coordinator.dispose();
    },
  );

  test('baseline inside discovers after dwell interval', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      discoveryRerollIntervalOverride: _shortReroll,
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [_siteJson(siteId: 1, lat: 51.0000, lon: 4.0000)],
                'total': 1,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            discoverCalls.add(int.parse(request.url.pathSegments[3]));
            return http.Response(
              jsonEncode(_discoverResponseJson(siteId: 1, lat: 51.0, lon: 4.0)),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(_inside);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(discoverCalls, isEmpty);

    await Future<void>.delayed(_shortReroll + const Duration(milliseconds: 40));
    expect(discoverCalls, [1]);
    expect(coordinator.pendingCelebration?.site.siteId, 1);

    coordinator.dispose();
  });

  test('skips discovery rolls while faster than max discovery speed', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [_siteJson(siteId: 1, lat: 51.0000, lon: 4.0000)],
                'total': 1,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            final siteId = int.parse(request.url.pathSegments[3]);
            discoverCalls.add(siteId);
            return http.Response(
              jsonEncode(
                _discoverResponseJson(siteId: siteId, lat: 51.0, lon: 4.0),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    // 15 m/s ≈ 54 km/h — above the 10 km/h default gate.
    final locationService = _FakeLocationService(_outside, speedMps: 15.0);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();

    locationService.setLocation(_inside, speedMps: 15.0);
    await pumpUntilIdle();
    expect(discoverCalls, isEmpty);

    // Slow to walking pace → roll proceeds.
    locationService.setLocation(const LatLng(51.00002, 4.0000), speedMps: 1.5);
    await pumpUntilIdle();
    expect(discoverCalls, [1]);

    coordinator.dispose();
  });

  test('auto-discovers on walk-in and ignores farther sites', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [
                  _siteJson(siteId: 1, lat: 51.0000, lon: 4.0000),
                  _siteJson(siteId: 2, lat: 51.0100, lon: 4.0000),
                ],
                'total': 2,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            final siteId = int.parse(request.url.pathSegments[3]);
            discoverCalls.add(siteId);
            return http.Response(
              jsonEncode(
                _discoverResponseJson(siteId: siteId, lat: 51.0, lon: 4.0),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(_outside);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(discoverCalls, isEmpty);

    locationService.setLocation(_inside);
    await pumpUntilIdle();

    expect(discoverCalls, [1]);
    expect(coordinator.pendingCelebration?.site.siteId, 1);

    coordinator.dispose();
  });

  test(
    'does not re-attempt while still inside after successful enter',
    () async {
      var discoverCount = 0;
      final coordinator = FieldDiscoveryCoordinator(
        siteService: SiteService(
          client: MockClient((request) async {
            if (request.url.path.contains('nearby-discoverable')) {
              return http.Response(
                jsonEncode({
                  'items': [_siteJson(siteId: 7, lat: 51.0000, lon: 4.0000)],
                  'total': 1,
                  'generated': 0,
                  'radius_km': 1.0,
                }),
                200,
              );
            }
            if (request.method == 'POST' &&
                request.url.path.contains('/discover')) {
              discoverCount++;
              return http.Response(
                jsonEncode(
                  _discoverResponseJson(siteId: 7, lat: 51.0, lon: 4.0),
                ),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      );

      final locationService = _FakeLocationService(_outside);
      coordinator.bind(locationService: locationService);
      await pumpUntilIdle();

      locationService.setLocation(_inside);
      await pumpUntilIdle();
      expect(discoverCount, 1);

      coordinator.consumeCelebration();
      locationService.setLocation(const LatLng(51.00005, 4.0000));
      await pumpUntilIdle();
      expect(discoverCount, 1);

      coordinator.dispose();
    },
  );

  test('re-attempts after exit beyond radius then re-enter', () async {
    var discoverCount = 0;
    final coordinator = FieldDiscoveryCoordinator(
      discoveryRerollIntervalOverride: const Duration(seconds: 60),
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [_siteJson(siteId: 9, lat: 51.0000, lon: 4.0000)],
                'total': 1,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            discoverCount++;
            // First enter misses; second enter succeeds.
            if (discoverCount == 1) {
              return _chanceMissResponse();
            }
            return http.Response(
              jsonEncode(_discoverResponseJson(siteId: 9, lat: 51.0, lon: 4.0)),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(_outside);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();

    locationService.setLocation(_inside);
    await pumpUntilIdle();
    expect(discoverCount, 1);
    expect(coordinator.pendingCelebration, isNull);

    // Exit beyond discover radius before dwell fires — clears scheduled re-roll.
    locationService.setLocation(_outside);
    await pumpUntilIdle();

    // Re-enter — immediate second attempt succeeds.
    locationService.setLocation(_inside);
    await pumpUntilIdle();
    expect(discoverCount, 2);
    expect(coordinator.pendingCelebration?.site.siteId, 9);

    coordinator.dispose();
  });

  test(
    'chance miss re-rolls after dwell interval while staying inside',
    () async {
      var discoverCount = 0;
      final coordinator = FieldDiscoveryCoordinator(
        discoveryRerollIntervalOverride: _shortReroll,
        siteService: SiteService(
          client: MockClient((request) async {
            if (request.url.path.contains('nearby-discoverable')) {
              return http.Response(
                jsonEncode({
                  'items': [_siteJson(siteId: 3, lat: 51.0000, lon: 4.0000)],
                  'total': 1,
                  'generated': 0,
                  'radius_km': 1.0,
                }),
                200,
              );
            }
            if (request.method == 'POST' &&
                request.url.path.contains('/discover')) {
              discoverCount++;
              if (discoverCount == 1) {
                return _chanceMissResponse();
              }
              return http.Response(
                jsonEncode(
                  _discoverResponseJson(siteId: 3, lat: 51.0, lon: 4.0),
                ),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        ),
      );

      final locationService = _FakeLocationService(_outside);
      coordinator.bind(locationService: locationService);
      await pumpUntilIdle();

      locationService.setLocation(_inside);
      await pumpUntilIdle();
      expect(discoverCount, 1);
      expect(coordinator.pendingCelebration, isNull);

      // GPS nudge before interval — no re-roll yet.
      locationService.setLocation(const LatLng(51.00008, 4.0000));
      await pumpUntilIdle();
      expect(discoverCount, 1);

      await Future<void>.delayed(
        _shortReroll + const Duration(milliseconds: 40),
      );
      expect(discoverCount, 2);
      expect(coordinator.pendingCelebration?.site.siteId, 3);

      coordinator.dispose();
    },
  );

  test('discovers map-ingested site when API cache was empty', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': <dynamic>[],
                'total': 0,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            final siteId = int.parse(request.url.pathSegments[3]);
            discoverCalls.add(siteId);
            return http.Response(
              jsonEncode(
                _discoverResponseJson(siteId: siteId, lat: 51.0, lon: 4.0),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(_outside);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(discoverCalls, isEmpty);

    coordinator.ingestMapSites([
      SiteSummary(
        siteId: 42,
        latitude: 51.0000,
        longitude: 4.0000,
        status: 'hidden',
      ),
    ]);
    // Still outside after ingest — marks seen-outside on next check.
    locationService.setLocation(const LatLng(50.9983, 4.0000));
    await pumpUntilIdle();
    expect(discoverCalls, isEmpty);

    locationService.setLocation(_inside);
    await pumpUntilIdle();

    expect(discoverCalls, [42]);
    expect(coordinator.pendingCelebration?.site.siteId, 42);

    coordinator.dispose();
  });

  test('hiding a site allows rediscovery after walk-out and walk-in', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [_siteJson(siteId: 5, lat: 51.0000, lon: 4.0000)],
                'total': 1,
                'generated': 0,
                'radius_km': 1.0,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path.contains('/discover')) {
            final siteId = int.parse(request.url.pathSegments[3]);
            discoverCalls.add(siteId);
            return http.Response(
              jsonEncode(
                _discoverResponseJson(siteId: siteId, lat: 51.0, lon: 4.0),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(_outside);
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();

    locationService.setLocation(_inside);
    await pumpUntilIdle();
    expect(discoverCalls, [5]);

    coordinator.consumeCelebration();
    coordinator.siteBecameHidden(
      SiteSummary(
        siteId: 5,
        latitude: 51.0000,
        longitude: 4.0000,
        status: 'hidden',
      ),
    );

    // Still standing inside after hide — baseline only, no discover.
    locationService.setLocation(const LatLng(51.00005, 4.0000));
    await pumpUntilIdle();
    expect(discoverCalls, [5]);

    // Walk out, then in again.
    locationService.setLocation(_outside);
    await pumpUntilIdle();
    locationService.setLocation(_inside);
    await pumpUntilIdle();
    expect(discoverCalls, [5, 5]);
    expect(coordinator.pendingCelebration?.site.siteId, 5);

    coordinator.dispose();
  });
}
