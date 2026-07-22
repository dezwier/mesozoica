import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/services/site_service.dart';
import 'package:mesozoica/widgets/cards/card_record_thumb.dart';
import 'package:mesozoica/widgets/cards/site_card_related_lists.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _curatedFossilImageUrl =
    'https://mesozoica-production.up.railway.app/media/fossils/100001.webp';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SiteCardFossils renders horizontal fossil thumbnails',
      (tester) async {
    final service = SiteService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 100001,
                'main_image_url': _curatedFossilImageUrl,
                'identified_name': 'Tyrannosaurus rex',
              },
              {'id': 100002, 'identified_name': 'Triceratops horridus'},
              {'id': 100003},
            ],
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
              width: 220,
              height: 80,
              child: SiteCardFossils(
                siteId: 50001,
                siteService: service,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(CardRecordThumb), findsNWidgets(3));
    expect(find.text('Tyrannosaurus rex'), findsOneWidget);
    expect(find.text('Triceratops horridus'), findsOneWidget);

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.scrollDirection, Axis.horizontal);

    final thumbBoxes = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => box.width != null && box.height != null)
        .where((box) => box.width == box.height && box.width == 56)
        .toList();
    expect(thumbBoxes.length, greaterThanOrEqualTo(3));
  });
}
