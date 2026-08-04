import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/widgets/cards/site_card_user_timeline.dart';

void main() {
  test('timeline entries empty without discovery', () {
    const site = SiteSummary(siteId: 1);
    expect(SiteCardUserTimeline.entriesFor(site), isEmpty);
  });

  test('timeline shows discovered walk without link', () {
    final site = SiteSummary(
      siteId: 2,
      howDiscovered: SiteSummary.howDiscoveredWalk,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
    );
    final entries = SiteCardUserTimeline.entriesFor(site);
    expect(entries, hasLength(1));
    expect(entries.single.moment, 'Discovered');
    expect(entries.single.howLabel, 'Walk');
    expect(entries.single.onHowTap, isNull);
  });

  test('timeline appends First on same discovery line', () {
    final site = SiteSummary(
      siteId: 4,
      howDiscovered: SiteSummary.howDiscoveredWalk,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
      viewerWasFirstDiscovery: true,
    );
    final entries = SiteCardUserTimeline.entriesFor(site);
    expect(entries, hasLength(1));
    expect(entries.single.moment, 'Discovered');
    expect(entries.single.howLabel, 'Walk');
    expect(entries.single.wasFirst, isTrue);
  });

  test('timeline shows identified between discovered and documented', () {
    final site = SiteSummary(
      siteId: 6,
      howDiscovered: SiteSummary.howDiscoveredWalk,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
      viewerHasIdentified: true,
      identifiedAt: DateTime.utc(2026, 7, 1, 13),
      status: 'identified',
      documented: true,
      documentedAt: DateTime.utc(2026, 7, 2, 12),
    );
    final entries = SiteCardUserTimeline.entriesFor(site);
    expect(
      entries.map((e) => e.moment),
      ['Discovered', 'Identified', 'Documented'],
    );
    expect(entries[1].whenLabel, isNot(equals('—')));
  });

  test('timeline appends First on same documented line', () {
    final site = SiteSummary(
      siteId: 5,
      howDiscovered: SiteSummary.howDiscoveredWalk,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
      viewerWasFirstDiscovery: true,
      documented: true,
      documentedAt: DateTime.utc(2026, 7, 2, 12),
      viewerWasFirstDocumentation: true,
    );
    final entries = SiteCardUserTimeline.entriesFor(site);
    expect(entries.map((e) => e.moment), ['Discovered', 'Documented']);
    expect(entries[0].howLabel, 'Walk');
    expect(entries[0].wasFirst, isTrue);
    expect(entries[1].howLabel, 'First');
    expect(entries[1].wasFirst, isTrue);
  });

  test('SiteSummary parses explored_distance_m', () {
    final site = SiteSummary.fromJson({
      'site_id': 11,
      'explored_distance_m': 42.5,
    });
    expect(site.exploredDistanceM, 42.5);
  });

  test('timeline aerial row is tappable when session id present', () {
    var tapped = false;
    final site = SiteSummary(
      siteId: 3,
      howDiscovered: SiteSummary.howDiscoveredAerialRecon,
      discoveredAt: DateTime.utc(2026, 7, 1, 12),
      discoveringSessionId: 7,
    );
    final entries = SiteCardUserTimeline.entriesFor(
      site,
      onAerialTap: () => tapped = true,
    );
    expect(entries.single.howLabel, 'Aerial recon');
    expect(entries.single.onHowTap, isNotNull);
    entries.single.onHowTap!();
    expect(tapped, isTrue);
  });

  test('SiteSummary parses discovery fields from json', () {
    final site = SiteSummary.fromJson({
      'site_id': 9,
      'how_discovered': 'aerial_recon',
      'discovered_at': '2026-07-01T12:00:00',
      'discovering_session_id': 42,
      'viewer_was_first_discovery': true,
      'documented_at': '2026-07-02T12:00:00',
      'viewer_was_first_documentation': true,
    });
    expect(site.howDiscovered, SiteSummary.howDiscoveredAerialRecon);
    expect(site.discoveringSessionId, 42);
    expect(site.discoveredAt?.toUtc(), DateTime.utc(2026, 7, 1, 12));
    expect(site.viewerWasFirstDiscovery, isTrue);
    expect(site.documentedAt?.toUtc(), DateTime.utc(2026, 7, 2, 12));
    expect(site.viewerWasFirstDocumentation, isTrue);
  });
}
