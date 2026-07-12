import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/services/fossil_service.dart';
import 'package:mesozoica/widgets/cards/dinosaur_card_fossil_list.dart';
import 'package:mesozoica/widgets/cards/fossil_card_dialog.dart';
import 'package:mesozoica/widgets/cards/fossil_card_image.dart';
import 'package:mesozoica/widgets/cards/fossil_turnable_card.dart';

const _curatedFossilImageUrl =
    'https://mesozoica-production.up.railway.app/media/fossils/100001.webp';

Map<String, dynamic> _fossilJson({
  required int id,
  String? mainImageUrl,
}) {
  return {
    'id': id,
    'dinosaur_id': 1,
    'dinosaur_name': 'Tyrannosaurus',
    'identified_name': 'Tyrannosaurus rex',
    'main_image_url': mainImageUrl,
    'dinosaur_main_image_url':
        'https://mesozoica-production.up.railway.app/media/dinosaurs/Tyrannosaurus.webp',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DinosaurCardFossilList renders fossils and opens dialog on tap',
      (tester) async {
    final service = FossilService(
      client: MockClient((request) async {
        expect(request.url.queryParameters['dinosaur_id'], '1');
        return http.Response(
          jsonEncode({
            'items': [
              _fossilJson(id: 100001, mainImageUrl: _curatedFossilImageUrl),
              _fossilJson(id: 100002),
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
      MaterialApp(
        home: Scaffold(
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

    await tester.pumpAndSettle();

    expect(find.byType(FossilCardImage), findsNWidgets(2));
  });

  testWidgets('showFossilCardDialog loads fossil card from API', (tester) async {
    final service = FossilService(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/fossils/100001'));
        return http.Response(
          jsonEncode(_fossilJson(id: 100001, mainImageUrl: _curatedFossilImageUrl)),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
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
    await tester.pump();
    expect(find.text('Loading fossil…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(FossilTurnableCard), findsOneWidget);
    expect(find.text('Tyrannosaurus rex'), findsWidgets);
  });
}
