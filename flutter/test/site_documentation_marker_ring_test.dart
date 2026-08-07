import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesozoica/features/discovery/discovery.dart';
import 'package:mesozoica/widgets/cards/site_card_image.dart';
import 'package:mesozoica/widgets/map/map_site_mini_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Position _position() => Position(
  latitude: 50,
  longitude: 4,
  timestamp: DateTime.utc(2026, 8, 6),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('site marker ring follows live documentation progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final site = SiteSummary(
      siteId: 7,
      latitude: 50,
      longitude: 4,
      status: 'identified',
      discoveredAt: DateTime.utc(2026, 8, 6),
      viewerHasIdentified: true,
      documentationProgress: 0,
      oddDinoCount: 0.5,
      oddFossilCount: 0.5,
      oddCompleteness: 0.5,
      oddQuality: 0.5,
      oddDepth: 0.5,
    );
    final controller = SiteExplorationController();
    controller.updateDiscoverySpeed(0.1);
    await controller.debugInitializeForTest(
      discoveredSitesProvider: () => [site],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: MapSiteMiniCard(site: site, selected: true, width: 64),
          ),
        ),
      ),
    );

    SiteDocumentationRingPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.foregroundPainter)
        .whereType<SiteDocumentationRingPainter>()
        .single;

    final start = painter().progress;
    expect(start, greaterThan(0));

    await controller.debugCreditElapsed(
      position: _position(),
      elapsed: const Duration(seconds: 1),
    );
    await tester.pump();

    expect(painter().progress, greaterThan(start));
    expect(find.byType(SiteDocumentationPulseOverlay), findsOneWidget);
    expect(
      tester
          .widget<SiteDocumentationPulseOverlay>(
            find.byType(SiteDocumentationPulseOverlay),
          )
          .active,
      isTrue,
    );

    final before = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((box) => box.color.a)
        .where((a) => a > 0 && a < 1)
        .toList();
    expect(before, isNotEmpty);

    await tester.pump(const Duration(milliseconds: 125));
    final after = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((box) => box.color.a)
        .where((a) => a > 0 && a < 1)
        .toList();
    expect(after, isNotEmpty);
    expect(after.first, isNot(closeTo(before.first, 0.001)));

    controller.dispose();
  });

  testWidgets('documented site marker overlays rating stars on its image', (
    tester,
  ) async {
    const site = SiteSummary(
      siteId: 8,
      documented: true,
      oddDinoCount: 0.9,
      oddFossilCount: 0.9,
      oddCompleteness: 0.9,
      oddQuality: 0.9,
      oddDepth: 0.1,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MapSiteMiniCard(site: site, width: 64)),
      ),
    );

    final stars = find.byIcon(Icons.star_rounded);
    expect(stars, findsNWidgets(5));
    expect(
      tester.getCenter(stars.first).dy,
      closeTo(tester.getCenter(find.byType(SiteCardImage)).dy, 0.1),
    );
    expect(tester.widget<Icon>(stars.first).size, closeTo(10.24, 0.01));
    expect(
      tester
          .widget<SiteDocumentationPulseOverlay>(
            find.byType(SiteDocumentationPulseOverlay),
          )
          .active,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
