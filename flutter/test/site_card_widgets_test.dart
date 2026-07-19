import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/widgets/cards/geologic_timeline.dart';
import 'package:mesozoica/widgets/cards/site_card_back.dart';
import 'package:mesozoica/widgets/cards/site_card_edge_facts.dart';
import 'package:mesozoica/widgets/cards/site_card_front.dart';
import 'package:mesozoica/widgets/cards/site_card_header.dart';
import 'package:mesozoica/widgets/cards/site_card_image.dart';
import 'package:mesozoica/widgets/cards/site_card_location_map.dart';
import 'package:mesozoica/widgets/cards/site_turnable_card.dart';
import 'package:mesozoica/widgets/map/fossil_marker.dart';

const _fixture = SiteSummary(
  siteId: 50001,
  latitude: 46.8797,
  longitude: -110.3626,
  countryCode: 'US',
  state: 'Montana',
  rockType: 'sandstone',
  formation: 'Hell Creek Formation',
  minAgeMa: 66,
  maxAgeMa: 68,
  siteTypeId: 1,
  siteTypePeriod: 'cretaceous',
  siteTypeRockType: 'sandstone',
  mainImageUrl:
      'https://mesozoica-production.up.railway.app/media/site-types/1.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SiteCardImage detects curated URLs', () {
    expect(
      SiteCardImage.isCuratedCardImageUrl(_fixture.mainImageUrl),
      isTrue,
    );
    expect(SiteCardImage.isCuratedCardImageUrl(null), isFalse);
    expect(
      SiteCardImage.isCuratedCardImageUrl('https://example.com/image.png'),
      isFalse,
    );
  });

  testWidgets('SiteCardHeader renders formation title and collection subtitle',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SiteCardHeader(site: _fixture),
        ),
      ),
    );

    expect(find.text('Hell Creek Formation'), findsOneWidget);
    expect(find.text('Collection #50001'), findsOneWidget);
  });

  testWidgets('SiteCardFront renders image, title, and collection id',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardFront(site: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SiteCardImage), findsOneWidget);
    expect(find.text('Hell Creek Formation'), findsOneWidget);
    expect(find.text('Collection #50001'), findsOneWidget);
    expect(find.byType(SiteCardEdgeFacts), findsNothing);
    expect(find.text('COORDINATES'), findsNothing);
    expect(find.text('COUNTRY'), findsNothing);
    expect(find.text('ROCK TYPE'), findsNothing);
  });

  testWidgets('SiteCardFront renders status badge for field sites', (tester) async {
    const fieldSite = SiteSummary(
      siteId: 1000000001,
      latitude: 40,
      longitude: -100,
      rockType: 'sandstone',
      siteTypePeriod: 'cretaceous',
      status: 'protected',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardFront(site: fieldSite),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Protected'), findsOneWidget);
  });

  testWidgets('SiteCardFront omits status badge when status is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardFront(site: _fixture),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Hidden'), findsNothing);
    expect(find.text('Protected'), findsNothing);
  });

  testWidgets('SiteCardBack renders timeline, attributes, map, and fossil record',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardBack(
                site: _fixture,
                mapTileLayerBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SiteCardLocationMap), findsOneWidget);
    expect(find.byType(GeologicTimeline), findsOneWidget);
    expect(find.byType(SiteCardEdgeFacts), findsOneWidget);
    expect(find.text('FOSSIL RECORD'), findsOneWidget);
    expect(find.text('TIME'), findsNothing);
    expect(find.text('COORDINATES'), findsOneWidget);
    expect(find.text('COUNTRY'), findsOneWidget);
    expect(find.text('PERIOD'), findsOneWidget);
    expect(find.text('ROCK TYPE'), findsOneWidget);
    expect(find.textContaining('46.88'), findsOneWidget);
    expect(find.textContaining('Montana'), findsOneWidget);
    expect(find.textContaining('Cretaceous, 66 – 68 Ma'), findsOneWidget);
    expect(find.textContaining('Sandstone'), findsOneWidget);
  });

  testWidgets('SiteTurnableCard composes front and back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteTurnableCard(
                site: _fixture,
                turnable: false,
                mapTileLayerBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(SiteCardFront), findsOneWidget);
    expect(find.byType(SiteCardBack), findsOneWidget);
  });

  testWidgets('SiteCardLocationMap shows site marker when coordinates exist',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              height: 180,
              child: SiteCardLocationMap(
                site: _fixture,
                tileLayerBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FossilMarker), findsOneWidget);
    expect(find.text('No location'), findsNothing);
  });
}
