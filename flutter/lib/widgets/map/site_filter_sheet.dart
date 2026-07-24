import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/site_map_filters.dart';
import '../common/drawer_sheet_sizes.dart';

class SiteFilterSheet extends StatefulWidget {
  const SiteFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.showStatusSection = true,
    this.showReconRoutesSection = false,
    this.showSortSection = false,
    this.canSortByDistance = true,
  });

  final SiteMapFilters initialFilters;
  final ValueChanged<SiteMapFilters> onApply;
  final bool showStatusSection;
  final bool showReconRoutesSection;

  /// Catalog-only: Random / Nearest / Discovered sorts.
  final bool showSortSection;

  /// When false, Nearest is shown disabled in the sort dropdown.
  final bool canSortByDistance;

  static Future<void> show(
    BuildContext context, {
    required SiteMapFilters initialFilters,
    required ValueChanged<SiteMapFilters> onApply,
    bool showStatusSection = true,
    bool showReconRoutesSection = false,
    bool showSortSection = false,
    bool canSortByDistance = true,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SiteFilterSheet(
        initialFilters: initialFilters,
        onApply: onApply,
        showStatusSection: showStatusSection,
        showReconRoutesSection: showReconRoutesSection,
        showSortSection: showSortSection,
        canSortByDistance: canSortByDistance,
      ),
    );
  }

  @override
  State<SiteFilterSheet> createState() => _SiteFilterSheetState();
}

class _SiteFilterSheetState extends State<SiteFilterSheet> {
  late Set<String> _pendingStatuses;
  late Set<String> _pendingPeriods;
  late Set<String> _pendingRockTypes;
  late Set<String> _pendingHowDiscovered;
  late RangeValues _pendingDiscoveryRange;
  late SiteCatalogSort _pendingSort;
  late bool _pendingShowPastReconRoutes;
  late final DateTime _windowStart;
  late final DateTime _windowEnd;
  bool _applied = false;

  static final _monthYear = DateFormat('MMM yyyy');

  @override
  void initState() {
    super.initState();
    final bounds = discoveryTimeWindowBounds();
    _windowStart = bounds.start;
    _windowEnd = bounds.end;
    _pendingStatuses = {...widget.initialFilters.statuses};
    _pendingPeriods = {...widget.initialFilters.periods};
    _pendingRockTypes = {...widget.initialFilters.rockTypes};
    _pendingHowDiscovered = {...widget.initialFilters.howDiscovered};
    _pendingSort = widget.initialFilters.sort;
    _pendingShowPastReconRoutes = widget.initialFilters.showPastAerialRoutes;
    _pendingDiscoveryRange = _rangeFromFilters(widget.initialFilters);
  }

  RangeValues _rangeFromFilters(SiteMapFilters filters) {
    final spanMs =
        _windowEnd.millisecondsSinceEpoch - _windowStart.millisecondsSinceEpoch;
    if (spanMs <= 0) return const RangeValues(0, 1);
    final after = filters.discoveredAfter?.toUtc() ?? _windowStart;
    final before = filters.discoveredBefore?.toUtc() ?? _windowEnd;
    final start = ((after.millisecondsSinceEpoch -
                _windowStart.millisecondsSinceEpoch) /
            spanMs)
        .clamp(0.0, 1.0);
    final end = ((before.millisecondsSinceEpoch -
                _windowStart.millisecondsSinceEpoch) /
            spanMs)
        .clamp(0.0, 1.0);
    return RangeValues(
      start <= end ? start : end,
      start <= end ? end : start,
    );
  }

  DateTime _dateAt(double t) {
    final spanMs =
        _windowEnd.millisecondsSinceEpoch - _windowStart.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      _windowStart.millisecondsSinceEpoch + (spanMs * t).round(),
      isUtc: true,
    );
  }

  bool get _discoveryTimeIsFullSpan =>
      _pendingDiscoveryRange.start <= 0.001 &&
      _pendingDiscoveryRange.end >= 0.999;

  SiteMapFilters _buildPendingFilters() {
    final after =
        _discoveryTimeIsFullSpan ? null : _dateAt(_pendingDiscoveryRange.start);
    final before =
        _discoveryTimeIsFullSpan ? null : _dateAt(_pendingDiscoveryRange.end);
    return SiteMapFilters(
      statuses: _pendingStatuses,
      periods: _pendingPeriods,
      rockTypes: _pendingRockTypes,
      howDiscovered: _pendingHowDiscovered,
      discoveredAfter: after,
      discoveredBefore: before,
      sort: widget.showSortSection ? _pendingSort : SiteCatalogSort.random,
      filterByStatus: widget.showStatusSection,
      showPastAerialRoutes: widget.showReconRoutesSection
          ? _pendingShowPastReconRoutes
          : false,
    );
  }

  void _commitPending() {
    if (_applied) return;
    _applied = true;
    widget.onApply(_buildPendingFilters());
  }

  void _clearPending() {
    setState(() {
      _pendingStatuses = {...siteStatusOptions};
      _pendingPeriods = {...sitePeriodOptions};
      _pendingRockTypes = {...siteRockTypeOptions};
      _pendingHowDiscovered = {...siteHowDiscoveredOptions};
      _pendingDiscoveryRange = const RangeValues(0, 1);
      _pendingSort = SiteCatalogSort.random;
      _pendingShowPastReconRoutes = false;
    });
  }

  void _toggle(Set<String> target, String value, bool? selected) {
    setState(() {
      if (selected ?? false) {
        target.add(value);
      } else {
        target.remove(value);
      }
    });
  }

  void _selectOnly(void Function(Set<String> next) assign, String value) {
    setState(() => assign({value}));
  }

  String _formatBound(double t) {
    if (t >= 0.999) return 'Today';
    return _monthYear.format(_dateAt(t).toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _commitPending();
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: DrawerSheetSizes.initialChildSize,
        minChildSize: DrawerSheetSizes.minChildSize,
        maxChildSize: DrawerSheetSizes.maxChildSize,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                'Filter sites',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showStatusSection) ...[
                          _sectionTitle(theme, 'Status'),
                          ...siteStatusOptions.map(
                            (value) => _checkboxTile(
                              theme: theme,
                              value: _pendingStatuses.contains(value),
                              label: siteFilterOptionLabel(value),
                              onChanged: (selected) =>
                                  _toggle(_pendingStatuses, value, selected),
                              onLongPress: () => _selectOnly(
                                (next) => _pendingStatuses = next,
                                value,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _sectionTitle(theme, 'Period'),
                        ...sitePeriodOptions.map(
                          (value) => _checkboxTile(
                            theme: theme,
                            value: _pendingPeriods.contains(value),
                            label: siteFilterOptionLabel(value),
                            onChanged: (selected) =>
                                _toggle(_pendingPeriods, value, selected),
                            onLongPress: () => _selectOnly(
                              (next) => _pendingPeriods = next,
                              value,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _sectionTitle(theme, 'Discovery'),
                        ...siteHowDiscoveredOptions.map(
                          (value) => _checkboxTile(
                            theme: theme,
                            value: _pendingHowDiscovered.contains(value),
                            label: siteFilterOptionLabel(value),
                            onChanged: (selected) => _toggle(
                              _pendingHowDiscovered,
                              value,
                              selected,
                            ),
                            onLongPress: () => _selectOnly(
                              (next) => _pendingHowDiscovered = next,
                              value,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(theme, 'Rock type'),
                        ...siteRockTypeOptions.map(
                          (value) => _checkboxTile(
                            theme: theme,
                            value: _pendingRockTypes.contains(value),
                            label: siteFilterOptionLabel(value),
                            onChanged: (selected) =>
                                _toggle(_pendingRockTypes, value, selected),
                            onLongPress: () => _selectOnly(
                              (next) => _pendingRockTypes = next,
                              value,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _sectionTitle(theme, 'Discovery time'),
              RangeSlider(
                values: _pendingDiscoveryRange,
                onChanged: (values) {
                  setState(() => _pendingDiscoveryRange = values);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      _formatBound(_pendingDiscoveryRange.start),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatBound(_pendingDiscoveryRange.end),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showSortSection) ...[
                const SizedBox(height: 16),
                _sectionTitle(theme, 'Sort'),
                _buildSortDropdown(context),
              ],
              if (widget.showReconRoutesSection) ...[
                const SizedBox(height: 16),
                _sectionTitle(theme, 'Overlays'),
                _checkboxTile(
                  theme: theme,
                  value: _pendingShowPastReconRoutes,
                  label: 'Past aerial routes (last 24h)',
                  onChanged: (selected) {
                    setState(() {
                      _pendingShowPastReconRoutes = selected ?? false;
                    });
                  },
                  onLongPress: () {
                    setState(() => _pendingShowPastReconRoutes = true);
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _buildPendingFilters().hasActiveFilters
                        ? _clearPending
                        : null,
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (widget.showSortSection &&
                          _pendingSort == SiteCatalogSort.distance &&
                          !widget.canSortByDistance) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Waiting for your current location to sort by nearest',
                            ),
                          ),
                        );
                        return;
                      }
                      _commitPending();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Unchecking options hides matching sites. '
                'Long-press a checkbox to keep only that option.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSortDropdown(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SiteCatalogSort>(
          value: _pendingSort,
          isExpanded: true,
          icon: Icon(
            Icons.expand_more,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          onChanged: (value) {
            if (value == null) return;
            if (value == SiteCatalogSort.distance &&
                !widget.canSortByDistance) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Waiting for your current location to sort by nearest',
                  ),
                ),
              );
              return;
            }
            setState(() => _pendingSort = value);
          },
          items: SiteCatalogSort.values
              .map(
                (sort) => DropdownMenuItem(
                  value: sort,
                  enabled: sort != SiteCatalogSort.distance ||
                      widget.canSortByDistance,
                  child: Text(sort.label),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _checkboxTile({
    required ThemeData theme,
    required bool value,
    required String label,
    required ValueChanged<bool?> onChanged,
    required VoidCallback onLongPress,
  }) {
    return SizedBox(
      height: 44,
      child: InkWell(
        onTap: () => onChanged(!value),
        onLongPress: onLongPress,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 44,
              child: IgnorePointer(
                child: Checkbox(
                  value: value,
                  onChanged: (_) {},
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
