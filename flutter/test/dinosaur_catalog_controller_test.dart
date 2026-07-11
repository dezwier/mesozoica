import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mesozoica/controllers/dinosaur_catalog_controller.dart';
import 'package:mesozoica/services/dinosaur_service.dart';

void main() {
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
              },
              {
                'id': 1,
                'name': 'Tyrannosaurus',
                'wikipedia_title': 'Tyrannosaurus',
                'cladogram': {},
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
    expect(controller.items.map((d) => d.name), ['Velociraptor', 'Tyrannosaurus']);

    controller.dispose();
  });
}
