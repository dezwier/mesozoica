import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesozoica/features/discovery/discovery.dart';
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
    controller.dispose();
  });
}
