import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/models/site_map_filters.dart';

void main() {
  SiteSummary site({String? status, String? period, String? rockType}) {
    return SiteSummary(
      siteId: 1,
      latitude: 1,
      longitude: 1,
      status: status,
      siteTypePeriod: period,
      rockType: rockType,
    );
  }

  test('default filters match all complete sites', () {
    final filters = SiteMapFilters(filterByStatus: true);
    expect(filters.hasActiveFilters, isFalse);
    expect(
      filters.matches(
        site(status: 'hidden', period: 'cretaceous', rockType: 'sandstone'),
      ),
      isTrue,
    );
  });

  test('status filter excludes other statuses in field mode', () {
    final filters = SiteMapFilters(
      statuses: {'discovered'},
      filterByStatus: true,
    );
    expect(filters.hasActiveFilters, isTrue);
    expect(
      filters.matches(
        site(status: 'hidden', period: 'cretaceous', rockType: 'sandstone'),
      ),
      isFalse,
    );
    expect(
      filters.matches(
        site(status: 'discovered', period: 'cretaceous', rockType: 'sandstone'),
      ),
      isTrue,
    );
  });

  test('status filter ignored when filterByStatus is false', () {
    final filters = SiteMapFilters(
      statuses: {'discovered'},
      filterByStatus: false,
    );
    expect(filters.hasActiveFilters, isFalse);
    expect(
      filters.matches(
        site(status: 'hidden', period: 'cretaceous', rockType: 'sandstone'),
      ),
      isTrue,
    );
  });

  test('period and rock type filters narrow matches', () {
    final filters = SiteMapFilters(
      periods: {'jurassic'},
      rockTypes: {'mudstone'},
    );
    expect(filters.hasActiveFilters, isTrue);
    expect(
      filters.matches(
        site(status: 'hidden', period: 'jurassic', rockType: 'mudstone'),
      ),
      isTrue,
    );
    expect(
      filters.matches(
        site(status: 'hidden', period: 'cretaceous', rockType: 'mudstone'),
      ),
      isFalse,
    );
    expect(
      filters.matches(
        site(status: 'hidden', period: 'jurassic', rockType: 'sandstone'),
      ),
      isFalse,
    );
  });

  test('empty checkbox group matches nothing', () {
    final filters = SiteMapFilters(periods: {});
    expect(
      filters.matches(site(period: 'jurassic', rockType: 'sandstone')),
      isFalse,
    );
  });

  test(
    'hiding past aerial routes counts as active filter but not marker key',
    () {
      final filters = SiteMapFilters(showPastAerialRoutes: false);
      expect(filters.hasActiveFilters, isTrue);
      expect(filters.markerFilterKey, 'all');
      expect(
        filters.copyWith(showPastAerialRoutes: true).hasActiveFilters,
        isFalse,
      );
    },
  );

  test('howDiscovered filter narrows matches', () {
    final filters = SiteMapFilters(howDiscovered: {'walk'});
    expect(filters.hasActiveFilters, isTrue);
    expect(
      filters.matches(
        SiteSummary(
          siteId: 1,
          latitude: 1,
          longitude: 1,
          howDiscovered: 'walk',
          siteTypePeriod: 'cretaceous',
          rockType: 'sandstone',
        ),
      ),
      isTrue,
    );
    expect(
      filters.matches(
        SiteSummary(
          siteId: 2,
          latitude: 1,
          longitude: 1,
          howDiscovered: 'aerial_recon',
          siteTypePeriod: 'cretaceous',
          rockType: 'sandstone',
        ),
      ),
      isFalse,
    );
  });

  test('discovery time range filters by discoveredAt', () {
    final after = DateTime.utc(2026, 1, 1);
    final before = DateTime.utc(2026, 6, 1);
    final filters = SiteMapFilters(
      discoveredAfter: after,
      discoveredBefore: before,
    );
    expect(filters.discoveryTimeActive(), isTrue);
    expect(
      filters.matches(
        SiteSummary(
          siteId: 1,
          latitude: 1,
          longitude: 1,
          discoveredAt: DateTime.utc(2026, 3, 15),
          siteTypePeriod: 'cretaceous',
          rockType: 'sandstone',
        ),
      ),
      isTrue,
    );
    expect(
      filters.matches(
        SiteSummary(
          siteId: 2,
          latitude: 1,
          longitude: 1,
          discoveredAt: DateTime.utc(2025, 1, 1),
          siteTypePeriod: 'cretaceous',
          rockType: 'sandstone',
        ),
      ),
      isFalse,
    );
    expect(
      filters.matches(
        SiteSummary(
          siteId: 3,
          latitude: 1,
          longitude: 1,
          siteTypePeriod: 'cretaceous',
          rockType: 'sandstone',
        ),
      ),
      isFalse,
    );
  });

  test('SiteCatalogSort api values', () {
    expect(SiteCatalogSort.distance.apiValue, 'distance');
    expect(SiteCatalogSort.discoveredAtDesc.apiValue, 'discovered_at_desc');
    expect(SiteCatalogSort.discoveredAtAsc.apiValue, 'discovered_at');
    expect(SiteCatalogSort.fromApiValue('distance'), SiteCatalogSort.distance);
  });

  test('default sort is nearest', () {
    expect(SiteMapFilters().sort, SiteCatalogSort.distance);
    expect(SiteMapFilters().hasActiveFilters, isFalse);
  });

  test('earliestSiteDiscovery picks oldest discoveredAt', () {
    final earliest = earliestSiteDiscovery([
      SiteSummary(
        siteId: 1,
        latitude: 1,
        longitude: 1,
        discoveredAt: DateTime.utc(2026, 6, 1),
      ),
      SiteSummary(
        siteId: 2,
        latitude: 1,
        longitude: 1,
        discoveredAt: DateTime.utc(2026, 1, 15),
      ),
      SiteSummary(siteId: 3, latitude: 1, longitude: 1),
    ]);
    expect(earliest, DateTime.utc(2026, 1, 15));
  });

  test('discoveryTimeWindowBounds uses earliest card day', () {
    final bounds = discoveryTimeWindowBounds(
      now: DateTime.utc(2026, 7, 24),
      earliestDiscovery: DateTime.utc(2026, 3, 10, 15, 30),
    );
    expect(bounds.start, DateTime.utc(2026, 3, 10));
    expect(bounds.end, DateTime.utc(2026, 7, 24));
  });

  test('discoveryTimeNaturalDaySpan is 0 for same-day discoveries', () {
    final today = DateTime.utc(2026, 7, 24, 18, 0);
    expect(
      discoveryTimeNaturalDaySpan(now: today, earliestDiscovery: today),
      0,
    );
    expect(
      discoveryTimeNaturalDaySpan(
        now: today,
        earliestDiscovery: DateTime.utc(2026, 7, 20),
      ),
      4,
    );
  });

  test('hasActiveCatalogFilters ignores inventory-only fields', () {
    final filters = SiteMapFilters(
      periods: {'cretaceous'},
      sort: SiteCatalogSort.discoveredAtDesc,
      filterByStatus: true,
      statuses: {'discovered'},
    );
    expect(filters.hasActiveCatalogFilters, isTrue);
    expect(
      SiteMapFilters(
        sort: SiteCatalogSort.discoveredAtDesc,
        filterByStatus: true,
        statuses: {'discovered'},
      ).hasActiveCatalogFilters,
      isFalse,
    );
  });

  test('matchesSiteType filters by period and rock', () {
    final filters = SiteMapFilters(
      periods: {'cretaceous'},
      rockTypes: {'sandstone'},
    );
    expect(
      filters.matchesSiteType(period: 'cretaceous', rockType: 'sandstone'),
      isTrue,
    );
    expect(
      filters.matchesSiteType(period: 'jurassic', rockType: 'sandstone'),
      isFalse,
    );
    expect(
      filters.matchesSiteType(period: 'cretaceous', rockType: 'shale'),
      isFalse,
    );
  });
}
