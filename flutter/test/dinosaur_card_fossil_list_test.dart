import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/controllers/catalog_mode_controller.dart';
import 'package:mesozoica/services/fossil_service.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_fossil_list.dart';
import 'package:mesozoica/widgets/cards/fossil_card_dialog.dart';
import 'package:mesozoica/widgets/cards/card_record_thumb.dart';
import 'package:mesozoica/widgets/cards/fossil_turnable_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _curatedFossilImageUrl =
    'https://mesozoica-production.up.railway.app/media/fossils/100001.webp';

Map<String, dynamic> _fossilJson({
  required int id,
  String? mainImageUrl,
  String? identifiedName,
}) {
  return {
    'id': id,
    'dinosaur_id': 1,
    'dinosaur_name': 'Tyrannosaurus',
    'identified_name': identifiedName ?? 'Tyrannosaurus rex',
    'main_image_url': mainImageUrl,
    'dinosaur_main_image_url':
        'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
  };
}

Widget _wrapWithCatalogMode(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => CatalogModeController()),
      ChangeNotifierProvider(create: (_) => AuthController()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets(
    'DinosaurCardFossilList renders fossils and opens dialog on tap',
    (tester) async {
      final service = FossilService(
        client: MockClient((request) async {
          expect(request.url.queryParameters['dinosaur_id'], '1');
          expect(request.url.queryParameters['data_source'], 'archive');
          return http.Response(
            jsonEncode({
              'items': [
                _fossilJson(id: 100001, mainImageUrl: _curatedFossilImageUrl),
                _fossilJson(id: 100002, identifiedName: 'Tyrannosaurus sp.'),
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
                width: 120,
                height: 260,
                child: DinosaurCardFossilList(
                  dinosaurId: 1,
                  fossilService: service,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(); // start FutureBuilder
      await tester.pump(); // complete MockClient future

      expect(find.byType(CardRecordThumb), findsNWidgets(2));
      expect(find.text('Tyrannosaurus rex'), findsOneWidget);
      expect(find.text('Tyrannosaurus sp.'), findsOneWidget);

      final thumbBoxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width != null && box.height != null)
          .where((box) => box.width == box.height)
          .toList();
      expect(thumbBoxes, isNotEmpty);
      for (final box in thumbBoxes) {
        expect(box.width, box.height);
      }
    },
  );

  testWidgets('showFossilCardDialog loads fossil card from API', (
    tester,
  ) async {
    final service = FossilService(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/fossils/100001'));
        expect(request.url.queryParameters['data_source'], 'archive');
        return http.Response(
          jsonEncode(
            _fossilJson(id: 100001, mainImageUrl: _curatedFossilImageUrl),
          ),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      _wrapWithCatalogMode(
        Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showFossilCardDialog(
                    context,
                    fossilId: 100001,
                    fossilService: service,
                  ),
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(); // open sheet + start load
    await tester.pump(); // complete fossil fetch
    expect(find.byType(FossilTurnableCard), findsOneWidget);
    expect(find.text('Tyrannosaurus rex'), findsWidgets);
  });
}
