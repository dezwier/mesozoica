import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart' hide MapController;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/controllers/map_controller.dart';
import 'package:mesozoica/models/site_map_filters.dart';
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
    String? status,
  }) {
    return {
      'site_id': siteId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (siteTypePeriod != null) 'site_type_period': siteTypePeriod,
      if (status != null) 'status': status,
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

  test('load sends data_source query param from catalog mode in archive mode', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.archive);

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
    expect(requests.first.queryParameters['data_source'], 'archive');

    controller.dispose();
  });

  test('field mode load paginates all field sites', () async {
    var listCalls = 0;
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/sites') &&
            request.method == 'GET' &&
            !request.url.path.contains('nearby')) {
          listCalls++;
          return http.Response(
            jsonEncode({
              'items': [
                siteJson(
                  siteId: 1000000001,
                  latitude: 51.0,
                  longitude: 4.0,
                ),
              ],
              'total': 1,
              'limit': 500,
              'offset': 0,
              'has_next': false,
            }),
            200,
          );
        }
        return http.Response('', 404);
      }),
    );

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.load();
    await pumpUntilIdle();

    expect(listCalls, 1);
    expect(controller.loadingComplete, isTrue);
    expect(controller.geoSites.length, 1);
    expect(
      controller.geoSites.single.siteId,
      1000000001,
    );

    controller.dispose();
  });

  test('show-all loads only sites in the given viewport bbox', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 42,
                latitude: 51.02,
                longitude: 4.02,
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.setShowAllFieldSites(true);
    expect(requests, isEmpty);

    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );
    await pumpUntilIdle();

    expect(requests, isNotEmpty);
    final params = requests.first.queryParameters;
    expect(params['show_all'], 'true');
    expect(params['min_lat'], '51.0');
    expect(params['max_lat'], '51.05');
    expect(params['min_lon'], '4.0');
    expect(params['max_lon'], '4.05');
    expect(controller.geoSites.single.siteId, 42);

    controller.dispose();
  });

  test('show-all uses the full viewport bbox without shrinking', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(siteId: 42, latitude: 51.0, longitude: 4.0),
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.setShowAllFieldSites(true);
    // ~2° span — previously auto-shrunk; now fetched as-is.
    final result = await controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(50.0, 3.0), const LatLng(52.0, 5.0)),
    );
    await pumpUntilIdle();

    expect(result, ShowAllLoadResult.success);
    expect(controller.geoSites, isNotEmpty);
    final showAll = requests
        .where((u) => u.queryParameters['show_all'] == 'true')
        .toList();
    expect(showAll, isNotEmpty);
    final last = showAll.last.queryParameters;
    expect(last['min_lat'], '50.0');
    expect(last['max_lat'], '52.0');
    expect(last['min_lon'], '3.0');
    expect(last['max_lon'], '5.0');

    controller.dispose();
  });

  test('show-all refuses when viewport has more than 1000 sites', () async {
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(siteId: 42, latitude: 51.02, longitude: 4.02),
            ],
            'total': 1001,
            'limit': 500,
            'offset': 0,
            'has_next': true,
          }),
          200,
        );
      }),
    );

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.setShowAllFieldSites(true);
    final result = await controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );

    expect(result, ShowAllLoadResult.tooMany);
    expect(controller.error, contains('Too many sites'));
    expect(controller.geoSites, isEmpty);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      startsWith('field:linked'),
    );

    controller.dispose();
  });

  test('show-all toggle keeps linked markers until API data arrives', () async {
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    var showAllCalls = 0;
    final service = SiteService(
      client: MockClient((request) async {
        final showAll = request.url.queryParameters['show_all'] == 'true';
        if (showAll) {
          showAllCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response(
            jsonEncode({
              'items': [
                siteJson(
                  siteId: 99,
                  latitude: 51.02,
                  longitude: 4.02,
                  status: 'hidden',
                ),
                siteJson(
                  siteId: 7,
                  latitude: 51.03,
                  longitude: 4.03,
                  status: 'discovered',
                ),
              ],
              'total': 2,
              'limit': 500,
              'offset': 0,
              'has_next': false,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 7,
                latitude: 51.02,
                longitude: 4.02,
                status: 'discovered',
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.load();
    await pumpUntilIdle();
    expect(controller.filteredGeoSites.single.siteId, 7);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      startsWith('field:linked'),
    );

    controller.setShowAllFieldSites(true);
    // Still linked until authoritative show-all lands — no cache pollution.
    expect(controller.filteredGeoSites.single.siteId, 7);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      startsWith('field:linked'),
    );

    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(showAllCalls, 1);
    expect(controller.filteredGeoSites.length, 2);
    expect(
      controller.filteredGeoSites.map((s) => s.siteId).toSet(),
      {7, 99},
    );
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      'field:all|all',
    );

    // Re-enable clears show-all and requires a fresh API load.
    controller.setShowAllFieldSites(false);
    controller.setShowAllFieldSites(true);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      startsWith('field:linked'),
    );
    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(showAllCalls, 2);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      'field:all|all',
    );

    controller.dispose();
  });

  test('show-all paginates until the viewport is fully loaded', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        final offset =
            int.parse(request.url.queryParameters['offset'] ?? '0');
        final siteId = offset == 0 ? 42 : 43;
        final hasNext = offset == 0;
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: siteId,
                latitude: 51.02,
                longitude: 4.02 + offset * 0.001,
              ),
            ],
            'total': 2,
            'limit': 500,
            'offset': offset,
            'has_next': hasNext,
          }),
          200,
        );
      }),
    );

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.setShowAllFieldSites(true);
    final result = await controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );

    expect(result, ShowAllLoadResult.success);
    expect(
      requests.where((u) => u.queryParameters['show_all'] == 'true').length,
      2,
    );
    expect(
      controller.geoSites.map((s) => s.siteId).toSet(),
      {42, 43},
    );
    expect(controller.totalCatalog, 2);

    controller.dispose();
  });

  test('show-all re-enable starts clean and refetches', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        final showAll = request.url.queryParameters['show_all'] == 'true';
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: showAll ? 42 : 7,
                latitude: 51.02,
                longitude: 4.02,
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );

    controller.load();
    await pumpUntilIdle();
    expect(controller.geoSites.single.siteId, 7);

    final bounds =
        LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05));
    controller.setShowAllFieldSites(true);
    controller.loadShowAllInBounds(bounds);
    await pumpUntilIdle();
    expect(controller.filteredGeoSites.single.siteId, 42);
    final showAllRequests = () => requests
        .where((u) => u.queryParameters['show_all'] == 'true')
        .length;
    expect(showAllRequests(), 1);

    controller.setShowAllFieldSites(false);
    expect(controller.geoSites.single.siteId, 7);

    controller.setShowAllFieldSites(true);
    // Clean slate: linked interim until the new fetch lands.
    expect(controller.filteredGeoSites.single.siteId, 7);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      startsWith('field:linked'),
    );

    controller.loadShowAllInBounds(bounds);
    await pumpUntilIdle();
    expect(showAllRequests(), 2);
    expect(controller.filteredGeoSites.single.siteId, 42);
    expect(
      controller.mapMarkerDatasetKey(isFieldMode: true),
      'field:all|all',
    );

    controller.dispose();
  });

  test('show-all coalesces in-flight load with newer bounds', () async {
    final requests = <Uri>[];
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        requests.add(request.url);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final minLat = request.url.queryParameters['min_lat'];
        final siteId = minLat == '60.0' ? 99 : 42;
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: siteId,
                latitude: double.parse(minLat ?? '50') + 0.02,
                longitude: 4.02,
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.setShowAllFieldSites(true);

    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(50.0, 3.0), const LatLng(50.05, 3.05)),
    );
    // Second idle while first is still loading — coalesced, not concurrent.
    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(60.0, 4.0), const LatLng(60.05, 4.05)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final showAll = requests
        .where((u) => u.queryParameters['show_all'] == 'true')
        .toList();
    // First request + one follow-up for pending bounds (never stacked).
    expect(showAll.length, 2);
    expect(showAll.last.queryParameters['min_lat'], '60.0');
    expect(controller.geoSites.single.siteId, 99);
    expect(controller.loadingComplete, isTrue);

    controller.dispose();
  });

  test('show-all ignores client filters so hidden sites stay visible', () async {
    final catalogMode = CatalogModeController();
    await catalogMode.initialize();
    await catalogMode.setDataSource(CatalogDataSource.field);

    final service = SiteService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              siteJson(
                siteId: 42,
                latitude: 51.02,
                longitude: 4.02,
                status: 'hidden',
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

    final controller = MapController(
      service: service,
      catalogModeController: catalogMode,
    );
    controller.applyFilters(
      SiteMapFilters(
        filterByStatus: true,
        statuses: {'discovered'},
      ),
    );
    controller.setShowAllFieldSites(true);
    controller.loadShowAllInBounds(
      LatLngBounds(const LatLng(51.0, 4.0), const LatLng(51.05, 4.05)),
    );
    await pumpUntilIdle();

    expect(controller.filteredGeoSites.single.siteId, 42);
    expect(controller.filteredGeoSites.single.status, 'hidden');

    controller.dispose();
  });
}
