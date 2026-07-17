import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/models/fossil.dart';
import 'package:mesozoica/services/fossil_service.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_fossil_map.dart';
import 'package:mesozoica/widgets/cards/fossil_turnable_card.dart';
import 'package:mesozoica/widgets/map/fossil_marker.dart';
import 'package:provider/provider.dart';

Widget _noTileLayer() => const SizedBox.shrink();

Map<String, dynamic> _fossilJson({
  required int id,
  double? latitude,
  double? longitude,
  String? identifiedName,
}) {
  return {
    'id': id,
    'dinosaur_id': 1,
    'dinosaur_name': 'Tyrannosaurus',
    'identified_name': identifiedName ?? 'Tyrannosaurus rex',
    'latitude': latitude,
    'longitude': longitude,
  };
}

FossilSummary _fossil({
  required int id,
  double? latitude,
  double? longitude,
}) {
  return FossilSummary.fromJson(
    _fossilJson(id: id, latitude: latitude, longitude: longitude),
  );
}

Widget _wrapWithCatalogMode(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => CatalogModeController(),
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fossil map helpers', () {
    test('geolocatedFossils keeps fossils with coordinates only', () {
      final fossils = [
        _fossil(id: 1, latitude: 46.8, longitude: -104.0),
        _fossil(id: 2),
        _fossil(id: 3, latitude: 40.0, longitude: null),
      ];

      final geolocated = geolocatedFossils(fossils);
      expect(geolocated, hasLength(1));
      expect(geolocated.first.id, 1);
    });

    test('boundsForFossils returns null when no coordinates', () {
      expect(boundsForFossils([_fossil(id: 1)]), isNull);
    });

    test('boundsForFossils wraps a single point', () {
      final bounds = boundsForFossils([
        _fossil(id: 1, latitude: 46.8, longitude: -104.0),
      ]);

      expect(bounds, isNotNull);
      expect(bounds!.north, 46.8);
      expect(bounds.south, 46.8);
      expect(bounds.east, -104.0);
      expect(bounds.west, -104.0);
    });

    test('latLngPointsForFossils maps modern coordinates', () {
      final points = latLngPointsForFossils([
        _fossil(id: 1, latitude: 46.8, longitude: -104.0),
        _fossil(id: 2, latitude: 35.0, longitude: 139.0),
      ]);

      expect(points, [
        const LatLng(46.8, -104.0),
        const LatLng(35.0, 139.0),
      ]);
    });

    test('centerForFossils returns point for single fossil', () {
      final center = centerForFossils([
        _fossil(id: 1, latitude: 20, longitude: 0),
      ]);

      expect(center.latitude, 20);
      expect(center.longitude, 0);
    });
  });

  testWidgets('DinosaurCardFossilMap renders markers for geolocated fossils',
      (tester) async {
    final service = FossilService(
      client: MockClient((request) async {
        expect(request.url.queryParameters['dinosaur_id'], '1');
        return http.Response(
          jsonEncode({
            'items': [
              _fossilJson(id: 100001, latitude: 20.0, longitude: 0.0),
              _fossilJson(id: 100002, latitude: 22.0, longitude: 5.0),
            ],
            'total': 2,
            'limit': 200,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      _wrapWithCatalogMode(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 180,
              child: DinosaurCardFossilMap(
                dinosaurId: 1,
                fossilService: service,
                tileLayerBuilder: _noTileLayer,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('No geolocated occurrences'), findsNothing);
    expect(find.byType(FossilMarker), findsNWidgets(2));
  });

  testWidgets('DinosaurCardFossilMap shows empty state without coordinates',
      (tester) async {
    final service = FossilService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              _fossilJson(id: 100001),
            ],
            'total': 1,
            'limit': 200,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      _wrapWithCatalogMode(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 180,
              child: DinosaurCardFossilMap(
                dinosaurId: 1,
                fossilService: service,
                tileLayerBuilder: _noTileLayer,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('No geolocated occurrences'), findsOneWidget);
    expect(find.byType(FossilMarker), findsNothing);
  });

  testWidgets('DinosaurCardFossilMap opens fossil card dialog on marker tap',
      (tester) async {
    final service = FossilService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              _fossilJson(id: 100001, latitude: 20.0, longitude: 0.0),
            ],
            'total': 1,
            'limit': 200,
            'offset': 0,
            'has_next': false,
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      _wrapWithCatalogMode(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 180,
              child: DinosaurCardFossilMap(
                dinosaurId: 1,
                fossilService: service,
                tileLayerBuilder: _noTileLayer,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FossilMarker), findsOneWidget);

    await tester.tap(find.byType(FossilMarker));
    await tester.pumpAndSettle();

    expect(find.byType(FossilTurnableCard), findsOneWidget);
    expect(find.text('Tyrannosaurus rex'), findsWidgets);
  });
}
