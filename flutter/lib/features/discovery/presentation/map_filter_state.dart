import '../../../models/site.dart';
import '../../../models/site_map_filters.dart';

/// Owns map-filter policy independently of loading and widget state.
class MapFilterState {
  SiteMapFilters value = SiteMapFilters();

  bool get hasActiveFilters => value.hasActiveFilters;
  String get markerKey => value.markerFilterKey;

  void apply(SiteMapFilters next, {required bool isFieldMode}) {
    value = next.copyWith(filterByStatus: isFieldMode);
  }

  void updateMode({required bool isFieldMode}) {
    value = value.copyWith(filterByStatus: isFieldMode);
  }

  List<SiteSummary> filter(Iterable<SiteSummary> sites) {
    if (!hasActiveFilters) return List.unmodifiable(sites);
    return List.unmodifiable(sites.where(value.matches));
  }
}
