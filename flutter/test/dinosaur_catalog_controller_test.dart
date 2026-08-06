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
    expect(
      capturedUri!.queryParameters.containsKey('has_custom_image'),
      isFalse,
    );
    expect(capturedUri!.queryParameters.containsKey('llm_enriched'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('diet'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('length_m_min'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('mass_kg_min'), isFalse);
    expect(capturedUri!.queryParameters['mode'], 'inventory');
    expect(controller.items.map((d) => d.name), [
      'Velociraptor',
      'Tyrannosaurus',
    ]);
    expect(controller.mode, DinoScreenMode.inventory);

    controller.dispose();
  });

  test('setMode catalog passes mode catalog', () async {
    Uri? capturedUri;
    final service = DinosaurService(
      client: MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'items': <Map<String, dynamic>>[],
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
    expect(controller.mode, DinoScreenMode.inventory);
    controller.setMode(DinoScreenMode.catalog);
    expect(controller.mode, DinoScreenMode.catalog);
    await controller.refresh();

    expect(capturedUri!.queryParameters['mode'], 'catalog');

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
    expect(
      capturedUris.last.queryParameters.containsKey('ma_younger'),
      isFalse,
    );
    expect(capturedUris.last.queryParameters['sort'], 'random');
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

    controller.dispose();
  });

  test('diet and size filters are sent as query params', () async {
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
      const DinosaurCatalogFilters(
        diets: {'carnivore', 'herbivore'},
        lengthMMin: 5,
        lengthMMax: 15,
        massKgMin: 1000,
        massKgMax: 20000,
      ),
    );

    expect(capturedUri, isNotNull);
    final diets = capturedUri!.queryParametersAll['diet'] ?? const [];
    expect(diets.toSet(), {'carnivore', 'herbivore'});
    expect(capturedUri!.queryParameters['length_m_min'], '5.0');
    expect(capturedUri!.queryParameters['length_m_max'], '15.0');
    expect(capturedUri!.queryParameters['mass_kg_min'], '1000.0');
    expect(capturedUri!.queryParameters['mass_kg_max'], '20000.0');
    expect(controller.hasActiveFilters, isTrue);

    controller.dispose();
  });

  test('default size ranges omit length and mass params', () async {
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
    await controller.applyFilters(const DinosaurCatalogFilters(diets: {}));

    expect(capturedUri!.queryParameters.containsKey('length_m_min'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('mass_kg_min'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('diet'), isFalse);
    expect(controller.hasActiveFilters, isFalse);

    controller.dispose();
  });
}
