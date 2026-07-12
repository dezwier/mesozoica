import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart' hide MapController;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/map_controller.dart';
import 'package:mesozoica/services/fossil_service.dart';

void main() {
  Map<String, dynamic> fossilJson({
    required int id,
    required String identifiedName,
    double? latitude,
    double? longitude,
  }) {
    return {
      'id': id,
      'dinosaur_id': 1,
      'dinosaur_name': 'Tyrannosaurus',
      'identified_name': identifiedName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
  }

  Future<void> pumpUntilIdle() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('load returns immediately and filters fossils incrementally', () async {
    final service = FossilService(
      client: MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                fossilJson(
                  id: 1,
                  identifiedName: 'With coords',
                  latitude: 10.0,
                  longitude: 20.0,
                ),
                fossilJson(
                  id: 2,
                  identifiedName: 'Missing coords',
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
              fossilJson(
                id: 3,
                identifiedName: 'Also with coords',
                latitude: -5.0,
                longitude: 30.0,
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
    expect(controller.geoFossils, isEmpty);

    await pumpUntilIdle();
    await pumpUntilIdle();
    expect(controller.geoFossils.length, 2);
    expect(controller.geoFossils.map((f) => f.id), [1, 3]);
    expect(controller.loadingComplete, isTrue);
    expect(controller.fossilBounds, isNotNull);
    expect(
      controller.fossilBounds,
      LatLngBounds(const LatLng(-5, 20), const LatLng(10, 30)),
    );
    expect(controller.error, isNull);

    controller.dispose();
  });

  test('load paginates until has_next is false', () async {
    final requests = <Uri>[];
    final service = FossilService(
      client: MockClient((request) async {
        requests.add(request.url);
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                fossilJson(
                  id: 1,
                  identifiedName: 'Page one',
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
              fossilJson(
                id: 2,
                identifiedName: 'Page two',
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
    expect(controller.geoFossils.length, 2);

    controller.dispose();
  });

  test('load does not restart when already loading or complete', () async {
    var callCount = 0;
    final service = FossilService(
      client: MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({
            'items': [
              fossilJson(
                id: 1,
                identifiedName: 'Only one',
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
    final service = FossilService(
      client: MockClient((request) async {
        callCount++;
        return http.Response(
          jsonEncode({
            'items': [
              fossilJson(
                id: 1,
                identifiedName: 'Only one',
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
    final service = FossilService(
      client: MockClient((request) async {
        callCount++;
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                fossilJson(
                  id: 1,
                  identifiedName: 'Page one',
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
              fossilJson(
                id: 2,
                identifiedName: 'Page two',
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
    expect(controller.geoFossils.length, 1);

    controller.pause();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.loading, isFalse);
    expect(controller.loadingComplete, isFalse);

    controller.load();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.geoFossils.length, 2);
    expect(controller.loadingComplete, isTrue);

    controller.dispose();
  });
}
