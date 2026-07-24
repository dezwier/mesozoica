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
    this.earliestDiscovery,
  });

  final SiteMapFilters initialFilters;
  final ValueChanged<SiteMapFilters> onApply;
  final bool showStatusSection;
  final bool showReconRoutesSection;

  /// Catalog-only: Nearest / Discovered sorts.
  final bool showSortSection;

  /// When false, Nearest falls back with a snackbar if selected.
  final bool canSortByDistance;

  /// Oldest discovery among current cards; drives the slider minimum day.
  final DateTime? earliestDiscovery;

  static Future<void> show(
    BuildContext context, {
    required SiteMapFilters initialFilters,
    required ValueChanged<SiteMapFilters> onApply,
    bool showStatusSection = true,
    bool showReconRoutesSection = false,
    bool showSortSection = false,
    bool canSortByDistance = true,
    DateTime? earliestDiscovery,
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
        earliestDiscovery: earliestDiscovery,
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
  late RangeValues _pendingDiscoveryDays;
  late SiteCatalogSort _pendingSort;
  late bool _pendingShowPastReconRoutes;
  late final DateTime _windowStart;
  late final DateTime _windowEnd;
  late final int _dayCount;
  bool _applied = false;

  static final _dayLabel = DateFormat('MMM d, yyyy');

  @override
  void initState() {
    super.initState();
    final bounds = discoveryTimeWindowBounds(
      earliestDiscovery: widget.earliestDiscovery,
    );
    _windowStart = bounds.start;
    _windowEnd = bounds.end;
    _dayCount = _windowEnd.difference(_windowStart).inDays;
    _pendingStatuses = {...widget.initialFilters.statuses};
    _pendingPeriods = {...widget.initialFilters.periods};
    _pendingRockTypes = {...widget.initialFilters.rockTypes};
    _pendingHowDiscovered = {...widget.initialFilters.howDiscovered};
    _pendingSort = widget.showSortSection
        ? widget.initialFilters.sort
        : SiteCatalogSort.distance;
    if (_pendingSort == SiteCatalogSort.distance &&
        !widget.canSortByDistance &&
        widget.showSortSection) {
      _pendingSort = SiteCatalogSort.discoveredAtDesc;
    }
    _pendingShowPastReconRoutes = widget.initialFilters.showPastAerialRoutes;
    _pendingDiscoveryDays = _daysFromFilters(widget.initialFilters);
  }

  RangeValues _daysFromFilters(SiteMapFilters filters) {
    if (_dayCount <= 0) return const RangeValues(0, 0);
    final after = filters.discoveredAfter == null
        ? _windowStart
        : discoveryDateOnlyUtc(filters.discoveredAfter!);
    final before = filters.discoveredBefore == null
        ? _windowEnd
        : discoveryDateOnlyUtc(filters.discoveredBefore!);
    final start = after
        .difference(_windowStart)
        .inDays
        .clamp(0, _dayCount)
        .toDouble();
    final end = before
        .difference(_windowStart)
        .inDays
        .clamp(0, _dayCount)
        .toDouble();
    return RangeValues(start <= end ? start : end, start <= end ? end : start);
  }

  DateTime _dateAtDay(double day) {
    final clamped = day.round().clamp(0, _dayCount);
    return _windowStart.add(Duration(days: clamped));
  }

  bool get _discoveryTimeIsFullSpan =>
      _dayCount <= 0 ||
      (_pendingDiscoveryDays.start <= 0.001 &&
          _pendingDiscoveryDays.end >= _dayCount - 0.001);

  SiteMapFilters _buildPendingFilters() {
    final after =
        _discoveryTimeIsFullSpan ? null : _dateAtDay(_pendingDiscoveryDays.start);
    // Inclusive end-of-day for the upper thumb.
    final before = _discoveryTimeIsFullSpan
        ? null
        : _dateAtDay(_pendingDiscoveryDays.end)
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
    return SiteMapFilters(
      statuses: _pendingStatuses,
      periods: _pendingPeriods,
      rockTypes: _pendingRockTypes,
      howDiscovered: _pendingHowDiscovered,
      discoveredAfter: after,
      discoveredBefore: before,
      sort: widget.showSortSection ? _pendingSort : SiteCatalogSort.distance,
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
      _pendingDiscoveryDays = RangeValues(0, _dayCount.toDouble());
      _pendingSort = widget.canSortByDistance
          ? SiteCatalogSort.distance
          : SiteCatalogSort.discoveredAtDesc;
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

  String _formatDay(double day) {
    if (_dayCount <= 0) return 'Today';
    if (day >= _dayCount - 0.001) return 'Today';
    return _dayLabel.format(_dateAtDay(day).toLocal());
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
              if (widget.showSortSection) ...[
                const SizedBox(height: 16),
                _sectionTitle(theme, 'Sort'),
                _buildSortDropdown(context),
              ],
              const SizedBox(height: 16),
              _sectionTitle(theme, 'Discovery time'),
              if (_dayCount <= 0)
                Text(
                  'No discovery dates on current sites yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                RangeSlider(
                  values: _pendingDiscoveryDays,
                  min: 0,
                  max: _dayCount.toDouble(),
                  divisions: _dayCount < 1 ? null : _dayCount,
                  onChanged: (values) {
                    setState(() => _pendingDiscoveryDays = values);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(
                        _formatDay(_pendingDiscoveryDays.start),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDay(_pendingDiscoveryDays.end),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (widget.showStatusSection)
                _checkboxDropdown(
                  theme: theme,
                  title: 'Status',
                  options: siteStatusOptions,
                  selected: _pendingStatuses,
                  onToggle: (value, selected) =>
                      _toggle(_pendingStatuses, value, selected),
                  onSelectOnly: (value) => _selectOnly(
                    (next) => _pendingStatuses = next,
                    value,
                  ),
                ),
              _checkboxDropdown(
                theme: theme,
                title: 'Period',
                options: sitePeriodOptions,
                selected: _pendingPeriods,
                onToggle: (value, selected) =>
                    _toggle(_pendingPeriods, value, selected),
                onSelectOnly: (value) => _selectOnly(
                  (next) => _pendingPeriods = next,
                  value,
                ),
              ),
              _checkboxDropdown(
                theme: theme,
                title: 'Discovery',
                options: siteHowDiscoveredOptions,
                selected: _pendingHowDiscovered,
                onToggle: (value, selected) =>
                    _toggle(_pendingHowDiscovered, value, selected),
                onSelectOnly: (value) => _selectOnly(
                  (next) => _pendingHowDiscovered = next,
                  value,
                ),
              ),
              _checkboxDropdown(
                theme: theme,
                title: 'Rock type',
                options: siteRockTypeOptions,
                selected: _pendingRockTypes,
                onToggle: (value, selected) =>
                    _toggle(_pendingRockTypes, value, selected),
                onSelectOnly: (value) => _selectOnly(
                  (next) => _pendingRockTypes = next,
                  value,
                ),
              ),
              if (widget.showReconRoutesSection) ...[
                const SizedBox(height: 8),
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
                      _commitPending();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
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

  Widget _checkboxDropdown({
    required ThemeData theme,
    required String title,
    required List<String> options,
    required Set<String> selected,
    required void Function(String value, bool? selected) onToggle,
    required void Function(String value) onSelectOnly,
  }) {
    final allSelected = selected.length == options.length;
    final subtitle = allSelected
        ? 'All'
        : selected.isEmpty
            ? 'None'
            : '${selected.length} of ${options.length}';

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final value in options)
            _checkboxTile(
              theme: theme,
              value: selected.contains(value),
              label: siteFilterOptionLabel(value),
              onChanged: (checked) => onToggle(value, checked),
              onLongPress: () => onSelectOnly(value),
            ),
        ],
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
