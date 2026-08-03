import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/services/site_service.dart';
import 'package:mesozoica/widgets/cards/card_record_thumb.dart';
import 'package:mesozoica/widgets/cards/site_card_related_lists.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _curatedFossilImageUrl =
    'https://mesozoica-production.up.railway.app/media/fossils/100001.webp';

const _adminProfile = Profile(
  id: 1,
  displayName: 'Admin',
  xp: 0,
  specialization: '',
  yearsOfExperience: 0,
  notableDiscovery: '',
  favoriteEra: '',
  level: 1,
  achievements: [],
  profileImage: '',
  bio: '',
  currentLocation: '',
  actualDinosaursCount: 0,
  actualFossilsCount: 0,
  actualSitesCount: 0,
  email: 'admin@example.com',
  isAdmin: true,
);

/// Mock honors `include_hidden=true` like the backend admin peek.
SiteService _mockService({
  required List<Map<String, dynamic>> visibleItems,
  List<Map<String, dynamic>> hiddenItems = const [],
}) {
  return SiteService(
    client: MockClient((request) async {
      final includeHidden =
          request.url.queryParameters['include_hidden'] == 'true';
      final items = [
        ...visibleItems,
        if (includeHidden) ...hiddenItems,
      ];
      return http.Response(jsonEncode({'items': items}), 200);
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SiteCardFossils renders horizontal fossil thumbnails',
      (tester) async {
    final service = _mockService(visibleItems: [
      {
        'id': 100001,
        'main_image_url': _curatedFossilImageUrl,
        'identified_name': 'Tyrannosaurus rex',
        'status': 'discovered',
      },
      {
        'id': 100002,
        'identified_name': 'Triceratops horridus',
        'status': 'in_situ',
      },
      {'id': 100003, 'status': 'discovered'},
    ]);

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

  testWidgets('SiteCardFossils hides hidden fossils outside admin mode',
      (tester) async {
    final service = _mockService(
      visibleItems: [
        {
          'id': 1,
          'identified_name': 'Visible Fossil',
          'status': 'discovered',
        },
      ],
      hiddenItems: [
        {
          'id': 2,
          'identified_name': 'Hidden Fossil',
          'status': 'hidden',
        },
      ],
    );
    final auth = AuthController();
    await auth.applyUser(_adminProfile);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
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

    expect(find.text('Visible Fossil'), findsOneWidget);
    expect(find.text('Hidden Fossil'), findsNothing);
    expect(find.byType(CardRecordThumb), findsOneWidget);
  });

  testWidgets('SiteCardFossils shows faded hidden fossils in admin mode',
      (tester) async {
    final service = _mockService(
      visibleItems: [
        {
          'id': 1,
          'identified_name': 'Visible Fossil',
          'status': 'discovered',
        },
      ],
      hiddenItems: [
        {
          'id': 2,
          'identified_name': 'Hidden Fossil',
          'status': 'hidden',
        },
      ],
    );
    final auth = AuthController();
    await auth.applyUser(_adminProfile);
    auth.setAdminModeEnabled(true);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
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

    expect(find.text('Visible Fossil'), findsOneWidget);
    expect(find.text('Hidden Fossil'), findsOneWidget);
    expect(find.byType(CardRecordThumb), findsNWidgets(2));

    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities, isNotEmpty);
    expect(opacities.any((o) => o.opacity == 0.5), isTrue);
  });
}
