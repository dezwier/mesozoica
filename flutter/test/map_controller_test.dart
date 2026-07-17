import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart' hide MapController;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/controllers/map_controller.dart';
import 'package:mesozoica/services/site_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Map<String, dynamic> siteJson({
    required int siteId,
    double? latitude,
    double? longitude,
    String? siteTypePeriod,
  }) {
    return {
      'site_id': siteId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (siteTypePeriod != null) 'site_type_period': siteTypePeriod,
    };
  }

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('load returns immediately and filters sites incrementally', () async {
    final service = SiteService(
      client: MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                siteJson(
                  siteId: 1,
                  latitude: 10.0,
                  longitude: 20.0,
                  siteTypePeriod: 'cretaceous',
                ),
                siteJson(
                  siteId: 2,
                ),
              ],
              'total': 3,
              'limit': 500,
              'offset': 0,
              'has_next': true,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 3,
                latitude: -5.0,
                longitude: 30.0,
                siteTypePeriod: 'jurassic',
              ),
            ],
            'total': 3,
            'limit': 500,
            'offset': 2,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();

    expect(controller.loading, isTrue);
    expect(controller.geoSites, isEmpty);

    await pumpUntilIdle();
    await pumpUntilIdle();
    expect(controller.geoSites.length, 2);
    expect(controller.geoSites.map((s) => s.siteId), [1, 3]);
    expect(controller.loadingComplete, isTrue);
    expect(controller.siteBounds, isNotNull);
    expect(
      controller.siteBounds,
      LatLngBounds(const LatLng(-5, 20), const LatLng(10, 30)),
    );
    expect(controller.error, isNull);

    controller.dispose();
  });

  test('load paginates until has_next is false', () async {
    final requests = <Uri>[];
    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                siteJson(
                  siteId: 1,
                  latitude: 1.0,
                  longitude: 1.0,
                ),
              ],
              'total': 2,
              'limit': 500,
              'offset': 0,
              'has_next': true,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 2,
                latitude: 2.0,
                longitude: 2.0,
              ),
            ],
            'total': 2,
            'limit': 500,
            'offset': 1,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();
    await pumpUntilIdle();
    await pumpUntilIdle();

    expect(requests.length, 2);
    expect(requests[0].queryParameters['offset'], '0');
    expect(requests[1].queryParameters['offset'], '1');
    expect(controller.geoSites.length, 2);

    controller.dispose();
  });

  test('load does not restart when already loading or complete', () async {
    var callCount = 0;
    final service = SiteService(
      client: MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 1,
                latitude: 0.0,
                longitude: 0.0,
              ),
            ],
            'total': 1,
            'limit': 500,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();
    controller.load();
    await pumpUntilIdle();

    expect(callCount, 1);

    controller.dispose();
  });

  test('refresh forces reload from scratch', () async {
    var callCount = 0;
    final service = SiteService(
      client: MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 1,
                latitude: 0.0,
                longitude: 0.0,
              ),
            ],
            'total': 1,
            'limit': 500,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();
    await pumpUntilIdle();
    await controller.refresh();
    await pumpUntilIdle();

    expect(callCount, 2);

    controller.dispose();
  });

  test('pause cancels in-flight pagination and load resumes', () async {
    var callCount = 0;
    final service = SiteService(
      client: MockClient((request) async {
        callCount++;
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                siteJson(
                  siteId: 1,
                  latitude: 1.0,
                  longitude: 1.0,
                ),
              ],
              'total': 3,
              'limit': 500,
              'offset': 0,
              'has_next': true,
            }),
            200,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 2,
                latitude: 2.0,
                longitude: 2.0,
              ),
            ],
            'total': 3,
            'limit': 500,
            'offset': 1,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();
    await pumpUntilIdle();
    expect(controller.geoSites.length, 1);

    controller.pause();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.loading, isFalse);
    expect(controller.loadingComplete, isFalse);

    controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.geoSites.length, 2);
    expect(controller.loadingComplete, isTrue);

    controller.dispose();
  });

  test('siteForDisplay fetches fresh site and updates cache', () async {
    var detailCalls = 0;
    final service = SiteService(
      client: MockClient((request) async {
        if (request.url.pathSegments.contains('sites') &&
            request.url.pathSegments.length == 4) {
          detailCalls++;
          return http.Response(
            jsonEncode({
              'site_id': 1,
              'latitude': 10.0,
              'longitude': 20.0,
              'formation': 'Hell Creek Formation',
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 1,
                latitude: 10.0,
                longitude: 20.0,
              ),
            ],
            'total': 1,
            'limit': 500,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(service: service);
    controller.load();
    await pumpUntilIdle();

    expect(controller.geoSites.single.formation, isNull);

    final displaySite = await controller.siteForDisplay(controller.geoSites.single);
    expect(detailCalls, 1);
    expect(displaySite.formation, 'Hell Creek Formation');
    expect(controller.geoSites.single.formation, 'Hell Creek Formation');

    controller.dispose();
  });

  test('load sends data_source query param from catalog mode', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'limit': 500,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.load();
    await pumpUntilIdle();

    expect(requests, isNotEmpty);
    expect(requests.first.queryParameters['data_source'], 'field');

    controller.dispose();
  });
}
