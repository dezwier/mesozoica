import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/controllers/fossil_catalog_controller.dart';
import 'package:mesozoica/services/fossil_service.dart';

void main() {
  const curatedImageUrl =
      'https://mesozoica-production.up.railway.app/media/fossils/100001.webp';

  Map<String, dynamic> fossilJson({
    required int id,
    required String identifiedName,
    String? mainImageUrl,
  }) {
    return {
      'id': id,
      'dinosaur_id': 1,
      'dinosaur_name': 'Tyrannosaurus',
      'identified_name': identifiedName,
      'main_image_url': mainImageUrl,
      'dinosaur_main_image_url':
          'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
    };
  }

  test('fetchFossils requests random sort with seed', () async {
    Uri? capturedUri;
    final service = FossilService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              fossilJson(
                id: 2,
                identifiedName: 'Specimen B',
                mainImageUrl: curatedImageUrl,
              ),
              fossilJson(
                id: 1,
                identifiedName: 'Specimen A',
                mainImageUrl: curatedImageUrl,
              ),
            ],
            'total': 2,
            'limit': 20,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = FossilCatalogController(service: service);
    await controller.load();

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'random');
    expect(capturedUri!.queryParameters['seed'], isNotEmpty);
    expect(capturedUri!.queryParameters['limit'], '20');
    expect(capturedUri!.queryParameters['offset'], '0');
    expect(capturedUri!.queryParameters.containsKey('q'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('ma_younger'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('ma_older'), isFalse);
    expect(capturedUri!.queryParameters['has_custom_image'], 'true');
    expect(
      controller.items.map((f) => f.identifiedName),
      ['Specimen B', 'Specimen A'],
    );

    controller.dispose();
  });

  test('applyFilters uses name sort when searching', () async {
    Uri? capturedUri;
    final service = FossilService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              fossilJson(
                id: 1,
                identifiedName: 'Tyrannosaurus rex',
                mainImageUrl: curatedImageUrl,
              ),
            ],
            'total': 1,
            'limit': 20,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = FossilCatalogController(service: service);
    await controller.applyFilters(
      const FossilCatalogFilters(searchQuery: 'tyrannosaurus'),
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'name');
    expect(capturedUri!.queryParameters['q'], 'tyrannosaurus');
    expect(capturedUri!.queryParameters.containsKey('seed'), isFalse);
    expect(controller.items.single.identifiedName, 'Tyrannosaurus rex');

    controller.dispose();
  });

  test('loadMore appends next page', () async {
    var callCount = 0;
    final service = FossilService(
      client: MockClient((request) async {
        callCount += 1;
        if (callCount == 1) {
          return http.Response(
            jsonEncode({
              'items': [
                fossilJson(
                  id: 1,
                  identifiedName: 'First',
                  mainImageUrl: curatedImageUrl,
                ),
              ],
              'total': 2,
              'limit': 20,
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
                identifiedName: 'Second',
                mainImageUrl: curatedImageUrl,
              ),
            ],
            'total': 2,
            'limit': 20,
            'offset': 1,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = FossilCatalogController(service: service);
    await controller.load();
    await controller.loadMore();

    expect(controller.items.map((f) => f.identifiedName), ['First', 'Second']);
    expect(controller.hasMore, isFalse);

    controller.dispose();
  });
}
