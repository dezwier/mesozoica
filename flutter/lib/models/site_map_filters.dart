import '../utils/display_text.dart';
import 'site.dart';

/// Site lifecycle statuses for field sites.
const siteStatusOptions = <String>[
  'hidden',
  'discovered',
  'surveyed',
  'excavation',
  'exhausted',
  'protected',
];

const sitePeriodOptions = <String>[
  'triassic',
  'jurassic',
  'cretaceous',
];

/// Mirrors backend `ROCK_TYPES` in site_service/rules.py.
const siteRockTypeOptions = <String>[
  'sandstone',
  'mudstone',
  'claystone',
  'siltstone',
  'marl',
  'conglomerate',
  'shale',
  'limestone',
  'siliciclastic',
  'coal',
  'lime mudstone',
  'carbonate',
  'tuff',
  'phosphorite',
  'chalk',
  'lignite',
  'chert',
  'wackestone',
  'gravel',
];

/// Mirrors backend `HOW_DISCOVERED_VALUES`.
const siteHowDiscoveredOptions = <String>[
  'walk',
  'aerial_recon',
  'aerial_scout',
  'manual',
];

String siteFilterOptionLabel(String value) {
  switch (value) {
    case 'aerial_recon':
      return 'Aerial recon';
    case 'aerial_scout':
      return 'Aerial scout';
    default:
      return capitalizeLeadingLetter(value);
  }
}

/// How far back past aerial recon routes stay eligible for the map overlay.
const Duration pastAerialRouteMaxAge = Duration(hours: 24);

/// Fallback discovery-time window when no card has a discovery date.
const Duration discoveryTimeWindowSpan = Duration(days: 365 * 2);

/// Catalog sort keys sent to `GET /sites`.
enum SiteCatalogSort {
  distance,
  discoveredAtDesc,
  discoveredAtAsc;

  String get label => switch (this) {
        SiteCatalogSort.distance => 'Nearest',
        SiteCatalogSort.discoveredAtDesc => 'Discovered (newest)',
        SiteCatalogSort.discoveredAtAsc => 'Discovered (oldest)',
      };

  String get apiValue => switch (this) {
        SiteCatalogSort.distance => 'distance',
        SiteCatalogSort.discoveredAtDesc => 'discovered_at_desc',
        SiteCatalogSort.discoveredAtAsc => 'discovered_at',
      };

  static SiteCatalogSort fromApiValue(String value) {
    return switch (value) {
      'discovered_at_desc' => SiteCatalogSort.discoveredAtDesc,
      'discovered_at' => SiteCatalogSort.discoveredAtAsc,
      _ => SiteCatalogSort.distance,
    };
  }
}

DateTime discoveryDateOnlyUtc(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Bounds for the discovery-time range slider (UTC day precision).
///
/// [earliestDiscovery] is typically the oldest `discoveredAt` among visible
/// cards; when null, falls back to [discoveryTimeWindowSpan] before today.
({DateTime start, DateTime end}) discoveryTimeWindowBounds({
  DateTime? now,
  DateTime? earliestDiscovery,
}) {
  final end = discoveryDateOnlyUtc(now ?? DateTime.now());
  final earliest = earliestDiscovery == null
      ? null
      : discoveryDateOnlyUtc(earliestDiscovery);
  final start = earliest ?? end.subtract(discoveryTimeWindowSpan);
  if (start.isAfter(end)) return (start: end, end: end);
  return (start: start, end: end);
}

/// Inclusive calendar-day distance from window start → end.
///
/// `0` means earliest and today are the same day (no meaningful day range).
int discoveryTimeNaturalDaySpan({
  DateTime? now,
  DateTime? earliestDiscovery,
}) {
  final bounds = discoveryTimeWindowBounds(
    now: now,
    earliestDiscovery: earliestDiscovery,
  );
  return bounds.end.difference(bounds.start).inDays;
}

/// Earliest non-null `discoveredAt` among [sites], or null if none.
DateTime? earliestSiteDiscovery(Iterable<SiteSummary> sites) {
  DateTime? earliest;
  for (final site in sites) {
    final at = site.discoveredAt?.toUtc();
    if (at == null) continue;
    if (earliest == null || at.isBefore(earliest)) earliest = at;
  }
  return earliest;
}

class SiteMapFilters {
  SiteMapFilters({
    Set<String>? statuses,
    Set<String>? periods,
    Set<String>? rockTypes,
    Set<String>? howDiscovered,
    this.discoveredAfter,
    this.discoveredBefore,
    this.sort = SiteCatalogSort.distance,
    this.filterByStatus = false,
    this.showPastAerialRoutes = false,
  })  : statuses = statuses ?? Set<String>.from(siteStatusOptions),
        periods = periods ?? Set<String>.from(sitePeriodOptions),
        rockTypes = rockTypes ?? Set<String>.from(siteRockTypeOptions),
        howDiscovered =
            howDiscovered ?? Set<String>.from(siteHowDiscoveredOptions);

  final Set<String> statuses;
  final Set<String> periods;
  final Set<String> rockTypes;
  final Set<String> howDiscovered;

  /// Inclusive lower bound for viewer discovery time (UTC). Null = unbound.
  final DateTime? discoveredAfter;

  /// Inclusive upper bound for viewer discovery time (UTC). Null = unbound.
  final DateTime? discoveredBefore;

  /// Catalog list sort (ignored by map marker filtering).
  final SiteCatalogSort sort;

  /// When false (archive mode), status checkboxes are ignored.
  final bool filterByStatus;

  /// Opt-in: show completed aerial recon polylines from the last 24h.
  final bool showPastAerialRoutes;

  bool get howDiscoveredActive =>
      howDiscovered.length != siteHowDiscoveredOptions.length;

  /// True when the dual slider is not at the full window.
  bool discoveryTimeActive({DateTime? earliestDiscovery, DateTime? now}) {
    if (discoveredAfter == null && discoveredBefore == null) return false;
    final bounds = discoveryTimeWindowBounds(
      now: now,
      earliestDiscovery: earliestDiscovery,
    );
    final after = discoveredAfter == null
        ? null
        : discoveryDateOnlyUtc(discoveredAfter!);
    final before = discoveredBefore == null
        ? null
        : discoveryDateOnlyUtc(discoveredBefore!);
    if (after != null && after.isAfter(bounds.start)) return true;
    if (before != null && before.isBefore(bounds.end)) return true;
    return false;
  }

  bool get hasActiveFilters {
    final periodActive = periods.length != sitePeriodOptions.length;
    final rockActive = rockTypes.length != siteRockTypeOptions.length;
    final statusActive =
        filterByStatus && statuses.length != siteStatusOptions.length;
    return periodActive ||
        rockActive ||
        statusActive ||
        howDiscoveredActive ||
        discoveryTimeActive() ||
        showPastAerialRoutes ||
        sort != SiteCatalogSort.distance;
  }

  /// Filters that apply to site-type catalog (period + rock only).
  bool get hasActiveCatalogFilters {
    final periodActive = periods.length != sitePeriodOptions.length;
    final rockActive = rockTypes.length != siteRockTypeOptions.length;
    return periodActive || rockActive;
  }

  /// Stable key so marker layer can wipe+reload when site filters change.
  /// Past recon routes / catalog sort do not affect this key.
  String get markerFilterKey {
    final periodActive = periods.length != sitePeriodOptions.length;
    final rockActive = rockTypes.length != siteRockTypeOptions.length;
    final statusActive =
        filterByStatus && statuses.length != siteStatusOptions.length;
    final howActive = howDiscoveredActive;
    final timeActive = discoveryTimeActive();
    if (!periodActive &&
        !rockActive &&
        !statusActive &&
        !howActive &&
        !timeActive) {
      return 'all';
    }
    final s = (statuses.toList()..sort()).join(',');
    final p = (periods.toList()..sort()).join(',');
    final r = (rockTypes.toList()..sort()).join(',');
    final h = (howDiscovered.toList()..sort()).join(',');
    final after = discoveredAfter?.toUtc().toIso8601String() ?? '';
    final before = discoveredBefore?.toUtc().toIso8601String() ?? '';
    return 's=$s|p=$p|r=$r|h=$h|a=$after|b=$before|fs=$filterByStatus';
  }

  SiteMapFilters copyWith({
    Set<String>? statuses,
    Set<String>? periods,
    Set<String>? rockTypes,
    Set<String>? howDiscovered,
    DateTime? discoveredAfter,
    DateTime? discoveredBefore,
    bool clearDiscoveryTime = false,
    SiteCatalogSort? sort,
    bool? filterByStatus,
    bool? showPastAerialRoutes,
  }) {
    return SiteMapFilters(
      statuses: statuses ?? this.statuses,
      periods: periods ?? this.periods,
      rockTypes: rockTypes ?? this.rockTypes,
      howDiscovered: howDiscovered ?? this.howDiscovered,
      discoveredAfter:
          clearDiscoveryTime ? null : (discoveredAfter ?? this.discoveredAfter),
      discoveredBefore: clearDiscoveryTime
          ? null
          : (discoveredBefore ?? this.discoveredBefore),
      sort: sort ?? this.sort,
      filterByStatus: filterByStatus ?? this.filterByStatus,
      showPastAerialRoutes: showPastAerialRoutes ?? this.showPastAerialRoutes,
    );
  }

  bool matches(SiteSummary site) {
    if (filterByStatus && statuses.length != siteStatusOptions.length) {
      if (statuses.isEmpty) return false;
      final status = site.status?.trim().toLowerCase();
      if (status == null || status.isEmpty || !statuses.contains(status)) {
        return false;
      }
    }

    if (periods.length != sitePeriodOptions.length) {
      if (periods.isEmpty) return false;
      final period = site.effectivePeriod?.trim().toLowerCase();
      if (period == null || period.isEmpty || !periods.contains(period)) {
        return false;
      }
    }

    if (rockTypes.length != siteRockTypeOptions.length) {
      if (rockTypes.isEmpty) return false;
      final rock =
          (site.rockType ?? site.siteTypeRockType)?.trim().toLowerCase();
      if (rock == null || rock.isEmpty || !rockTypes.contains(rock)) {
        return false;
      }
    }

    if (howDiscoveredActive) {
      if (howDiscovered.isEmpty) return false;
      final how = site.howDiscovered?.trim().toLowerCase();
      if (how == null || how.isEmpty || !howDiscovered.contains(how)) {
        return false;
      }
    }

    if (discoveryTimeActive()) {
      final at = site.discoveredAt?.toUtc();
      if (at == null) return false;
      final after = discoveredAfter?.toUtc();
      final before = discoveredBefore?.toUtc();
      if (after != null && at.isBefore(after)) return false;
      if (before != null && at.isAfter(before)) return false;
    }

    return true;
  }

  /// Period / rock matching for site-type catalog rows.
  bool matchesSiteType({
    required String period,
    required String rockType,
  }) {
    if (periods.length != sitePeriodOptions.length) {
      if (periods.isEmpty) return false;
      final value = period.trim().toLowerCase();
      if (value.isEmpty || !periods.contains(value)) return false;
    }

    if (rockTypes.length != siteRockTypeOptions.length) {
      if (rockTypes.isEmpty) return false;
      final value = rockType.trim().toLowerCase();
      if (value.isEmpty || !rockTypes.contains(value)) return false;
    }

    return true;
  }
}
