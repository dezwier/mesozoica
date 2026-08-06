import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/models/site_map_filters.dart';
import 'package:mesozoica/widgets/cards/site_card_back.dart';

void main() {
  test('field site needs identification shows Excavation Site title', () {
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

  test('identified field site uses period and rock title', () {
    final site = SiteSummary(
      siteId: 1000000067,
      discoveredAt: DateTime.utc(2026, 8, 1),
      viewerHasIdentified: true,
      siteTypePeriod: 'cretaceous',
      rockType: 'sandstone',
      status: 'discovered',
    );
    expect(site.needsIdentification, isFalse);
    expect(site.displayTitle, 'Cretaceous Sandstone');
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

  testWidgets('unidentified site shows empty dimensions and Identify button', (
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
    expect(find.text('Identify'), findsOneWidget);
    expect(find.text('Identify site to begin documentation'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'Documented \d+% · Explored')),
      findsNothing,
    );
  });
}
