import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/controllers/tool_catalog_controller.dart';
import 'package:mesozoica/services/tool_service.dart';

void main() {
  MockClient _mockClient({
    required void Function(Uri uri) onToolsRequest,
    List<Map<String, dynamic>> categories = const [
      {'value': '1 site_discovery', 'label': 'Site Discovery'},
      {'value': '2 fossil_discovery', 'label': 'Fossil Discovery'},
    ],
  }) {
    return MockClient((request) async {
      if (request.url.path.endsWith('/tools/categories')) {
        return http.Response(jsonEncode({'items': categories}), 200);
      }
      onToolsRequest(request.url);
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': 2,
              'name': 'Air Scribe',
              'category': '5 preparation',
              'scientific_tool': 'air scribe',
              'description': 'Desc.',
              'rarity': 1,
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
          'has_next': false,
        }),
        200,
      );
    });
  }

  test('load requests spawn_date sort by default in inventory', () async {
    Uri? capturedUri;
    final service = ToolService(
      client: _mockClient(onToolsRequest: (uri) => capturedUri = uri),
    );

    final controller = ToolCatalogController(service: service);
    await controller.load();

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'spawn_date');
    expect(capturedUri!.queryParameters.containsKey('seed'), isFalse);
    expect(capturedUri!.queryParameters.containsKey('q'), isFalse);
    expect(controller.hasActiveFilters, isFalse);
    expect(controller.availableCategories, hasLength(2));

    controller.dispose();
  });

  test('applyFilters passes search and name sort', () async {
    Uri? capturedUri;
    final service = ToolService(
      client: _mockClient(onToolsRequest: (uri) => capturedUri = uri),
    );

    final controller = ToolCatalogController(service: service);
    await controller.applyFilters(
      const ToolCatalogFilters(searchQuery: 'air', sort: ToolCatalogSort.name),
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'name');
    expect(capturedUri!.queryParameters.containsKey('seed'), isFalse);
    expect(capturedUri!.queryParameters['q'], 'air');
    expect(controller.hasActiveFilters, isTrue);

    controller.dispose();
  });

  test('applyFilters passes category filter and seed', () async {
    Uri? capturedUri;
    final service = ToolService(
      client: _mockClient(onToolsRequest: (uri) => capturedUri = uri),
    );

    final controller = ToolCatalogController(service: service);
    await controller.applyFilters(
      const ToolCatalogFilters(
        sort: ToolCatalogSort.category,
        categories: {'1 site_discovery', '5 preparation'},
      ),
    );

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['sort'], 'category');
    expect(capturedUri!.queryParameters['seed'], isNotEmpty);
    expect(
      capturedUri!.queryParametersAll['category'],
      containsAll(['1 site_discovery', '5 preparation']),
    );
    expect(controller.hasActiveFilters, isTrue);

    controller.dispose();
  });

  test('applyFilters passes show_all for catalog mode', () async {
    Uri? capturedUri;
    final service = ToolService(
      client: _mockClient(onToolsRequest: (uri) => capturedUri = uri),
    );

    final controller = ToolCatalogController(service: service);
    controller.setMode(ToolScreenMode.catalog);
    expect(controller.mode, ToolScreenMode.catalog);
    expect(controller.showAll, isTrue);
    await controller.refresh();

    expect(capturedUri, isNotNull);
    expect(capturedUri!.queryParameters['mode'], 'catalog');
    expect(capturedUri!.queryParameters['show_all'], 'true');

    controller.dispose();
  });

  test('default mode is inventory and catalog is allowed', () async {
    final service = ToolService(client: _mockClient(onToolsRequest: (_) {}));

    final controller = ToolCatalogController(service: service);
    expect(controller.mode, ToolScreenMode.inventory);
    controller.setMode(ToolScreenMode.catalog);
    expect(controller.mode, ToolScreenMode.catalog);
    expect(controller.showAll, isTrue);

    controller.dispose();
  });
}
