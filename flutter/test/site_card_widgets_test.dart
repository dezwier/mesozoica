import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/controllers/site_exploration_controller.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/widgets/cards/geologic_timeline.dart';
import 'package:mesozoica/widgets/cards/site_card_back.dart';
import 'package:mesozoica/widgets/cards/site_card_dimensions.dart';
import 'package:mesozoica/widgets/cards/site_card_front.dart';
import 'package:mesozoica/widgets/cards/site_card_header.dart';
import 'package:mesozoica/widgets/cards/site_card_image.dart';
import 'package:mesozoica/widgets/cards/site_card_location_map.dart';
import 'package:mesozoica/widgets/cards/site_card_related_lists.dart';
import 'package:mesozoica/widgets/cards/site_turnable_card.dart';
import 'package:mesozoica/widgets/map/fossil_marker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/game_config_test_helpers.dart';

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
  oddDinoCount: 0.42,
  oddFossilCount: 0.55,
  oddCompleteness: 0.61,
  oddQuality: 0.33,
  oddDepth: 0.78,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await loadGameConfigForTest();
  });

  testWidgets('Site dimensions shows active documenting progress', (
    tester,
  ) async {
    final site = _fixture.copyWith(
      status: 'identified',
      viewerHasIdentified: true,
      discoveredAt: DateTime.utc(2026, 8, 6),
      documentationProgress: 0,
    );
    final controller = SiteExplorationController();
    await controller.debugInitializeForTest(
      discoveredSitesProvider: () => [site],
    );
    await controller.debugCreditElapsed(
      position: Position(
        latitude: site.latitude!,
        longitude: site.longitude!,
        timestamp: DateTime.utc(2026, 8, 6),
        accuracy: 1,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
      elapsed: const Duration(seconds: 1),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: SiteCardDimensions(site: site)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Documenting site'), findsOneWidget);
    expect(find.text('Explored'), findsNothing);
    controller.dispose();
  });

  testWidgets('Site dimensions shows completed documentation state', (
    tester,
  ) async {
    final site = _fixture.copyWith(documented: true, documentationProgress: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SiteCardDimensions(site: site)),
      ),
    );
    await tester.pump();

    expect(find.text('Site documented'), findsOneWidget);
    expect(find.text('100%'), findsWidgets);
  });

  tearDown(() {
    GameConfig.debugReset();
  });

  test('SiteCardImage detects curated URLs', () {
    expect(SiteCardImage.isCuratedCardImageUrl(_fixture.mainImageUrl), isTrue);
    expect(SiteCardImage.isCuratedCardImageUrl(null), isFalse);
    expect(
      SiteCardImage.isCuratedCardImageUrl('https://example.com/image.png'),
      isFalse,
    );
  });

  testWidgets(
    'SiteCardHeader renders period-rock title and collection subtitle',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SiteCardHeader(site: _fixture)),
        ),
      );

      expect(find.text('Cretaceous Sandstone'), findsOneWidget);
      expect(find.text('#50001, 46.88, -110.36, Montana, US'), findsOneWidget);
    },
  );

  testWidgets('site quality stars appear on front but not back', (
    tester,
  ) async {
    final documented = _fixture.copyWith(
      documented: true,
      viewerHasDocumented: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SiteCardFront(site: documented)),
      ),
    );

    // Fixture score is 42.6 after reversing depth, which yields three stars.
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(
      tester.getCenter(find.byIcon(Icons.star_rounded).first).dy,
      lessThan(tester.getTopLeft(find.text('Cretaceous Sandstone')).dy),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SiteCardBack(
            site: documented,
            mapTileLayerBuilder: () => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  test('SiteSummary.displaySubtitle formats id comma and distance', () {
    expect(_fixture.displaySubtitle(), '#50001, 46.88, -110.36, Montana, US');
    expect(
      _fixture.displaySubtitle(distanceMeters: 450),
      '#50001, 46.88, -110.36, Montana, US, 450m',
    );
    expect(
      _fixture.displaySubtitle(distanceMeters: 1230),
      '#50001, 46.88, -110.36, Montana, US, 1.23km',
    );
    expect(SiteSummary.formatSiteDistance(999), '999m');
    expect(SiteSummary.formatSiteDistance(1000), '1.00km');
  });

  testWidgets('SiteCardFront renders image, title, and collection id', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 800, child: SiteCardFront(site: _fixture)),
          ),
        ),
      ),
    );

    expect(find.byType(SiteCardImage), findsOneWidget);
    expect(find.text('Cretaceous Sandstone'), findsOneWidget);
    expect(find.text('#50001, 46.88, -110.36, Montana, US'), findsOneWidget);
    expect(find.text('COORDINATES'), findsNothing);
    expect(find.text('COUNTRY'), findsNothing);
    expect(find.text('ROCK TYPE'), findsNothing);
  });

  testWidgets('SiteCardFront renders status badge for field sites', (
    tester,
  ) async {
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
            child: SizedBox(width: 800, child: SiteCardFront(site: fieldSite)),
          ),
        ),
      ),
    );

    expect(find.text('Protected'), findsOneWidget);
    expect(find.text('#1 · Original'), findsOneWidget);
    expect(find.text('40.00, -100.00'), findsOneWidget);
  });

  testWidgets('SiteCardFront omits status badge when status is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 800, child: SiteCardFront(site: _fixture)),
          ),
        ),
      ),
    );

    expect(find.text('Hidden'), findsNothing);
    expect(find.text('Protected'), findsNothing);
  });

  testWidgets('SiteCardBack renders timeline, dimensions, map, and fossils', (
    tester,
  ) async {
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
    final archiveTimeline = tester.widget<GeologicTimeline>(
      find.byType(GeologicTimeline),
    );
    // Archive sites reveal geology immediately, so the age band is shown.
    expect(archiveTimeline.birth, 68);
    expect(archiveTimeline.death, 66);
    expect(find.byType(SiteCardDimensions), findsOneWidget);
    expect(find.byType(SiteCardFossils), findsOneWidget);
    expect(find.text('Cretaceous Sandstone'), findsOneWidget);
    expect(find.text('#50001, 46.88, -110.36, Montana, US'), findsNothing);
    expect(find.textContaining('Discovered'), findsNothing);
    expect(find.text('SITE DIMENSIONS'), findsNothing);
    expect(find.textContaining('Site dimensions'), findsNothing);
    expect(find.text('Move within range to continue'), findsOneWidget);
    expect(find.text('COORDINATES'), findsNothing);
    expect(find.text('COUNTRY'), findsNothing);
    expect(find.text('PERIOD'), findsNothing);
    expect(find.text('ROCK TYPE'), findsNothing);
    expect(find.textContaining('GENERA PRESENCE'), findsOneWidget);
    expect(find.textContaining('FOSSIL PRESENCE'), findsOneWidget);
    expect(find.textContaining('COMPLETENESS'), findsOneWidget);
    expect(find.textContaining('PRESERVATION'), findsOneWidget);
    expect(find.textContaining('DEPTH'), findsOneWidget);
    // Skill L1 + absolute noise (±30 pts) → inline % labels, not a fixed 1%.
    expect(find.textContaining('%'), findsWidgets);
    expect(find.text('MOMENT'), findsNothing);
    expect(find.text('WHEN'), findsNothing);
    expect(find.text('HOW'), findsNothing);
    expect(find.text('0.42'), findsNothing);
    expect(find.text('0.55'), findsNothing);
  });

  testWidgets('SiteCardBack shows documentation progress when discovered', (
    tester,
  ) async {
    final discovered = SiteSummary(
      siteId: 1000000067,
      latitude: 46.8797,
      longitude: -110.3626,
      countryCode: 'US',
      state: 'Montana',
      rockType: 'sandstone',
      siteTypePeriod: 'cretaceous',
      siteTypeRockType: 'sandstone',
      status: 'discovered',
      howDiscovered: SiteSummary.howDiscoveredWalk,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
      viewerHasIdentified: true,
      documentationProgress: 0.30,
      oddDinoCount: 0.42,
      oddFossilCount: 0.55,
      oddCompleteness: 0.61,
      oddQuality: 0.33,
      oddDepth: 0.78,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardBack(
                site: discovered,
                mapTileLayerBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Discovered'), findsOneWidget);
    expect(find.textContaining(' · '), findsWidgets);
    expect(find.text('Mapped 30m'), findsNothing);
    expect(find.text('Move within range to continue'), findsOneWidget);
    expect(find.text('MOMENT'), findsNothing);
    // Skill + noise + 30m exploration → inline % labels (not a fixed 31%).
    expect(find.textContaining('%'), findsWidgets);
    expect(find.textContaining('DEPTH'), findsOneWidget);
  });

  testWidgets(
    'SiteCardBack omits Discovered subtitle when discoveredAt is set',
    (tester) async {
      final discovered = SiteSummary(
        siteId: 1000000067,
        latitude: 46.8797,
        longitude: -110.3626,
        countryCode: 'US',
        state: 'Montana',
        rockType: 'sandstone',
        siteTypePeriod: 'cretaceous',
        siteTypeRockType: 'sandstone',
        minAgeMa: 66,
        maxAgeMa: 68,
        version: 'Original',
        discoveredAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        viewerHasIdentified: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: SiteCardBack(
                  site: discovered,
                  mapTileLayerBuilder: () => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      final timeline = tester.widget<GeologicTimeline>(
        find.byType(GeologicTimeline),
      );
      // Field geology (incl. age band) stays hidden until documented.
      expect(timeline.birth, isNull);
      expect(timeline.death, isNull);

      // Header subtitle is suppressed; discovery still appears in the Timeline.
      expect(find.text('Discovered 3h ago'), findsNothing);
      expect(find.text('Original - Discovered 3h ago'), findsNothing);
      expect(find.text('#67'), findsNothing);
      expect(find.text('#67 · Original'), findsNothing);
      expect(find.text('Move within range to continue'), findsOneWidget);
    },
  );

  testWidgets(
    'SiteCardBack shows geologic age band after documentation',
    (tester) async {
      final documented = SiteSummary(
        siteId: 1000000067,
        latitude: 46.8797,
        longitude: -110.3626,
        countryCode: 'US',
        state: 'Montana',
        rockType: 'sandstone',
        siteTypePeriod: 'cretaceous',
        siteTypeRockType: 'sandstone',
        minAgeMa: 66,
        maxAgeMa: 68,
        documented: true,
        viewerHasDocumented: true,
        viewerHasIdentified: true,
        discoveredAt: DateTime.utc(2026, 7, 1, 12),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: SiteCardBack(
                  site: documented,
                  mapTileLayerBuilder: () => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final timeline = tester.widget<GeologicTimeline>(
        find.byType(GeologicTimeline),
      );
      expect(timeline.birth, 68);
      expect(timeline.death, 66);
    },
  );

  testWidgets('SiteTurnableCard composes front and back', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: SiteTurnableCard(
                  site: _fixture,
                  turnable: true,
                  mapTileLayerBuilder: () => const SizedBox.shrink(),
                ),
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

  testWidgets('SiteCardLocationMap shows site marker when coordinates exist', (
    tester,
  ) async {
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
