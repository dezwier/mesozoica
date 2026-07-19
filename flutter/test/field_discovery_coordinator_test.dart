import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/field_discovery_coordinator.dart';
import 'package:mesozoica/models/site.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  });

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  test('auto-discovers when within 50m and ignores farther sites', () async {
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
                _siteJson(siteId: siteId, lat: 51.0, lon: 4.0, status: 'discovered'),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    // ~11m from site 1, ~1.1km from site 2
    final locationService = _FakeLocationService(const LatLng(51.0001, 4.0000));
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();

    expect(discoverCalls, [1]);
    expect(coordinator.pendingCelebration?.siteId, 1);

    coordinator.dispose();
  });

  test('does not discover the same site twice', () async {
    var discoverCount = 0;
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [
                  _siteJson(siteId: 7, lat: 51.0000, lon: 4.0000),
                ],
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
                _siteJson(siteId: 7, lat: 51.0, lon: 4.0, status: 'discovered'),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0001, 4.0000));
    coordinator.bind(locationService: locationService);
    await pumpUntilIdle();
    expect(discoverCount, 1);

    coordinator.consumeCelebration();
    locationService.setLocation(const LatLng(51.00005, 4.0000));
    await pumpUntilIdle();
    expect(discoverCount, 1);

    coordinator.dispose();
  });

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
                _siteJson(
                  siteId: siteId,
                  lat: 51.0,
                  lon: 4.0,
                  status: 'discovered',
                ),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0001, 4.0000));
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
    locationService.setLocation(const LatLng(51.00005, 4.0000));
    await pumpUntilIdle();

    expect(discoverCalls, [42]);
    expect(coordinator.pendingCelebration?.siteId, 42);

    coordinator.dispose();
  });

  test('hiding a site allows rediscovery on the next move', () async {
    final discoverCalls = <int>[];
    final coordinator = FieldDiscoveryCoordinator(
      siteService: SiteService(
        client: MockClient((request) async {
          if (request.url.path.contains('nearby-discoverable')) {
            return http.Response(
              jsonEncode({
                'items': [
                  _siteJson(siteId: 5, lat: 51.0000, lon: 4.0000),
                ],
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
                _siteJson(
                  siteId: siteId,
                  lat: 51.0,
                  lon: 4.0,
                  status: 'discovered',
                ),
              ),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
    );

    final locationService = _FakeLocationService(const LatLng(51.0001, 4.0000));
    coordinator.bind(locationService: locationService);
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

    locationService.setLocation(const LatLng(51.00005, 4.0000));
    await pumpUntilIdle();
    expect(discoverCalls, [5, 5]);
    expect(coordinator.pendingCelebration?.siteId, 5);

    coordinator.dispose();
  });
}
