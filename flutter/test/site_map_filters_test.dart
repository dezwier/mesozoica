import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/models/site_map_filters.dart';

void main() {
  SiteSummary site({
    String? status,
    String? period,
    String? rockType,
  }) {
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
    expect(filters.matches(site(period: 'jurassic', rockType: 'sandstone')), isFalse);
  });

  test('showPastReconRoutes counts as active filter but not marker key', () {
    final filters = SiteMapFilters(showPastReconRoutes: true);
    expect(filters.hasActiveFilters, isTrue);
    expect(filters.markerFilterKey, 'all');
    expect(filters.copyWith(showPastReconRoutes: false).hasActiveFilters, isFalse);
  });
}
