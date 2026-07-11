import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/controllers/dinosaur_catalog_controller.dart';
import 'package:mesozoica/services/dinosaur_service.dart';

void main() {
  const curatedImageUrl =
      'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp';

  test('fetchDinosaurs requests random sort with seed', () async {
    Uri? capturedUri;
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 2,
                'name': 'Velociraptor',
                'wikipedia_title': 'Velociraptor',
                'cladogram': {},
                'main_image_url': curatedImageUrl,
              },
              {
                'id': 1,
                'name': 'Tyrannosaurus',
                'wikipedia_title': 'Tyrannosaurus',
                'cladogram': {},
                'main_image_url': curatedImageUrl,
              },
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

    final controller = DinosaurCatalogController(service: service);
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
    expect(controller.items.map((d) => d.name), ['Velociraptor', 'Tyrannosaurus']);

    controller.dispose();
  });

  test('applyFilters uses name sort when searching', () async {
    Uri? capturedUri;
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 1,
                'name': 'Tyrannosaurus',
                'wikipedia_title': 'Tyrannosaurus',
                'cladogram': {},
                'main_image_url': curatedImageUrl,
              },
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

    final controller = DinosaurCatalogController(service: service);
    await controller.applyFilters(
      const DinosaurCatalogFilters(
        searchQuery: 'tyranno',
        maYounger: 70,
        maOlder: 80,
      ),
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'name');
    expect(capturedUri!.queryParameters.containsKey('seed'), isFalse);
    expect(capturedUri!.queryParameters['q'], 'tyranno');
    expect(capturedUri!.queryParameters.containsKey('ma_younger'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('ma_older'), isFalse);
    expect(capturedUri!.queryParameters['has_custom_image'], 'true');
    expect(controller.hasActiveFilters, isTrue);
    expect(controller.total, 1);
    expect(controller.items.single.name, 'Tyrannosaurus');

    controller.dispose();
  });

  test('clearFilters omits filter params', () async {
    final capturedUris = <Uri>[];
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUris.add(request.url);
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'limit': 20,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = DinosaurCatalogController(service: service);
    await controller.applyFilters(
      const DinosaurCatalogFilters(searchQuery: 'raptor'),
    );
    await controller.clearFilters();

    expect(capturedUris.length, 2);
    expect(capturedUris.first.queryParameters['q'], 'raptor');
    expect(capturedUris.last.queryParameters.containsKey('q'), isFalse);
    expect(capturedUris.last.queryParameters.containsKey('ma_younger'), isFalse);
    expect(capturedUris.last.queryParameters['sort'], 'random');
    expect(capturedUris.last.queryParameters['has_custom_image'], 'true');
    expect(controller.hasActiveFilters, isFalse);

    controller.dispose();
  });

  test('full time range does not send ma params', () async {
    Uri? capturedUri;
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'limit': 20,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = DinosaurCatalogController(service: service);
    await controller.applyFilters(DinosaurCatalogFilters.defaults);

    expect(capturedUri!.queryParameters.containsKey('ma_younger'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('ma_older'), isFalse);
    expect(capturedUri!.queryParameters['has_custom_image'], 'true');

    controller.dispose();
  });

  test('onlyCustomImage false omits has_custom_image param', () async {
    Uri? capturedUri;
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': [],
            'total': 0,
            'limit': 20,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = DinosaurCatalogController(service: service);
    await controller.applyFilters(
      const DinosaurCatalogFilters(onlyCustomImage: false),
    );

    expect(capturedUri!.queryParameters.containsKey('has_custom_image'), isFalse);
    expect(controller.hasActiveFilters, isTrue);

    controller.dispose();
  });

  test('onlyCustomImage scans client-side when API ignores filter', () async {
    final capturedUris = <Uri>[];
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUris.add(request.url);
        final limit = int.parse(request.url.queryParameters['limit'] ?? '20');
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (limit == 20 && offset == 0) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 1,
                  'name': 'Alpha',
                  'wikipedia_title': 'Alpha',
                  'cladogram': {},
                },
                {
                  'id': 2,
                  'name': 'Beta',
                  'wikipedia_title': 'Beta',
                  'cladogram': {},
                  'main_image_url': curatedImageUrl,
                },
              ],
              'total': 3,
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
              {
                'id': 2,
                'name': 'Beta',
                'wikipedia_title': 'Beta',
                'cladogram': {},
                'main_image_url': curatedImageUrl,
              },
              {
                'id': 3,
                'name': 'Gamma',
                'wikipedia_title': 'Gamma',
                'cladogram': {},
                'main_image_url': curatedImageUrl,
              },
              {
                'id': 1,
                'name': 'Alpha',
                'wikipedia_title': 'Alpha',
                'cladogram': {},
              },
            ],
            'total': 3,
            'limit': 500,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    final controller = DinosaurCatalogController(service: service);
    await controller.load();

    expect(capturedUris.length, 2);
    expect(capturedUris.first.queryParameters['has_custom_image'], 'true');
    expect(capturedUris.last.queryParameters.containsKey('has_custom_image'), isFalse);
    expect(controller.total, 2);
    expect(
      controller.items.map((d) => d.name).toSet(),
      {'Beta', 'Gamma'},
    );
    expect(controller.hasMore, isFalse);

    controller.dispose();
  });
}
