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

String siteFilterOptionLabel(String value) => capitalizeLeadingLetter(value);

class SiteMapFilters {
  SiteMapFilters({
    Set<String>? statuses,
    Set<String>? periods,
    Set<String>? rockTypes,
    this.filterByStatus = false,
  })  : statuses = statuses ?? Set<String>.from(siteStatusOptions),
        periods = periods ?? Set<String>.from(sitePeriodOptions),
        rockTypes = rockTypes ?? Set<String>.from(siteRockTypeOptions);

  final Set<String> statuses;
  final Set<String> periods;
  final Set<String> rockTypes;

  /// When false (archive mode), status checkboxes are ignored.
  final bool filterByStatus;

  bool get hasActiveFilters {
    final periodActive = periods.length != sitePeriodOptions.length;
    final rockActive = rockTypes.length != siteRockTypeOptions.length;
    final statusActive =
        filterByStatus && statuses.length != siteStatusOptions.length;
    return periodActive || rockActive || statusActive;
  }

  /// Stable key so marker layer can wipe+reload when filters change.
  String get markerFilterKey {
    if (!hasActiveFilters) return 'all';
    final s = (statuses.toList()..sort()).join(',');
    final p = (periods.toList()..sort()).join(',');
    final r = (rockTypes.toList()..sort()).join(',');
    return 's=$s|p=$p|r=$r|fs=$filterByStatus';
  }

  SiteMapFilters copyWith({
    Set<String>? statuses,
    Set<String>? periods,
    Set<String>? rockTypes,
    bool? filterByStatus,
  }) {
    return SiteMapFilters(
      statuses: statuses ?? this.statuses,
      periods: periods ?? this.periods,
      rockTypes: rockTypes ?? this.rockTypes,
      filterByStatus: filterByStatus ?? this.filterByStatus,
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

    return true;
  }
}
