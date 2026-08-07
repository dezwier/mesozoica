import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/models/site_map_filters.dart';
import 'package:mesozoica/widgets/cards/site_card_back.dart';

void main() {
  test('field site keeps title hidden until documentation', () {
    final site = SiteSummary(
      siteId: 1000000067,
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: false,
      status: 'discovered',
    );
    expect(site.needsIdentification, isTrue);
    expect(site.canIdentify, isTrue);
    expect(site.displayTitle, 'Excavation Site');
  });

  test('identification alone does not reveal field site title', () {
    final site = SiteSummary(
      siteId: 1000000067,
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: true,
      siteTypePeriod: 'cretaceous',
      rockType: 'sandstone',
      status: 'discovered',
    );
    expect(site.needsIdentification, isFalse);
    expect(site.displayTitle, 'Excavation Site');
  });

  test('documentation reveals field site title and calculated stars', () {
    const site = SiteSummary(
      siteId: 1000000067,
      documented: true,
      siteTypePeriod: 'cretaceous',
      rockType: 'sandstone',
      oddDinoCount: 0.7,
      oddFossilCount: 0.5,
      oddCompleteness: 0.5,
      oddQuality: 0.5,
      oddDepth: 0.3,
    );
    expect(site.displayTitle, 'Cretaceous Sandstone');
    // (70 + 50 + 50 + 50 + reversed depth 70) / 5 = 58 → 4 stars.
    expect(site.documentationStars, 4);
  });

  test('documentation stars use 23/43/57/77 boundaries and inverted depth', () {
    SiteSummary siteAt(double score) => SiteSummary(
      siteId: 1000000067,
      documented: true,
      oddDinoCount: score,
      oddFossilCount: score,
      oddCompleteness: score,
      oddQuality: score,
      oddDepth: 1 - score,
    );

    expect(siteAt(0.22).documentationStars, 1);
    expect(siteAt(0.23).documentationStars, 2);
    expect(siteAt(0.42).documentationStars, 2);
    expect(siteAt(0.43).documentationStars, 3);
    expect(siteAt(0.56).documentationStars, 3);
    expect(siteAt(0.57).documentationStars, 4);
    expect(siteAt(0.76).documentationStars, 4);
    expect(siteAt(0.77).documentationStars, 5);
  });

  test('unknown period and rock filters match unidentified sites', () {
    final filters = SiteMapFilters(
      periods: {'unknown'},
      rockTypes: {'unknown'},
    );
    final unidentified = SiteSummary(
      siteId: 1000000067,
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: false,
      status: 'discovered',
    );
    final identified = SiteSummary(
      siteId: 1000000068,
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: true,
      siteTypePeriod: 'jurassic',
      rockType: 'mudstone',
      status: 'discovered',
    );
    expect(filters.matches(unidentified), isTrue);
    expect(filters.matches(identified), isFalse);
    expect(siteFilterOptionLabel('unknown'), 'Unknown');
  });

  testWidgets('discovered site immediately shows documentation mode', (
    tester,
  ) async {
    final site = SiteSummary(
      siteId: 1000000067,
      latitude: 46.8797,
      longitude: -110.3626,
      status: 'discovered',
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              child: SiteCardBack(
                site: site,
                mapTileLayerBuilder: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Excavation Site'), findsOneWidget);
    expect(find.text('Identify'), findsNothing);
    expect(find.text('Identify site to begin documentation'), findsNothing);
    expect(find.text('Move within range to continue'), findsOneWidget);
  });
}
