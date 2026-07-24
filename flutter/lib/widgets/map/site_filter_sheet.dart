import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/site_map_filters.dart';
import '../common/drawer_sheet_sizes.dart';
import '../profile/settings_form_styles.dart';

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

  void _toggle(Set<String> target, String value, bool selected) {
    setState(() {
      if (selected) {
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
    final outlineBorder = SettingsFormStyles.outlineBorder(context);

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
                const SizedBox(height: 20),
                SettingsFormStyles.settingsRow(
                  context: context,
                  label: 'Sort',
                  description: 'Order catalog cards in the list.',
                  controlWidth: 168,
                  control: SettingsFormStyles.densePopupField<SiteCatalogSort>(
                    context: context,
                    outlineBorder: outlineBorder,
                    selectedChild: Text(
                      _pendingSort.label,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    entries: [
                      for (final sort in SiteCatalogSort.values)
                        DensePopupEntry(
                          value: sort,
                          enabled: sort != SiteCatalogSort.distance ||
                              widget.canSortByDistance,
                          child: Text(
                            sort.label,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                    onSelected: (value) {
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
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Discovery time',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Limit sites by when you discovered them.',
                style: SettingsFormStyles.finePrintStyle(context),
              ),
              if (_dayCount <= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No discovery dates on current sites yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
              if (widget.showStatusSection) ...[
                const SizedBox(height: 20),
                _multiSelectRow(
                  context: context,
                  outlineBorder: outlineBorder,
                  label: 'Status',
                  description: 'Lifecycle stage of field sites.',
                  options: siteStatusOptions,
                  selected: _pendingStatuses,
                  onToggle: (value, selected) =>
                      _toggle(_pendingStatuses, value, selected),
                  onSelectOnly: (value) => _selectOnly(
                    (next) => _pendingStatuses = next,
                    value,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _multiSelectRow(
                context: context,
                outlineBorder: outlineBorder,
                label: 'Period',
                description: 'Geologic period of the site.',
                options: sitePeriodOptions,
                selected: _pendingPeriods,
                onToggle: (value, selected) =>
                    _toggle(_pendingPeriods, value, selected),
                onSelectOnly: (value) => _selectOnly(
                  (next) => _pendingPeriods = next,
                  value,
                ),
              ),
              const SizedBox(height: 20),
              _multiSelectRow(
                context: context,
                outlineBorder: outlineBorder,
                label: 'Discovery',
                description: 'How the site was found.',
                options: siteHowDiscoveredOptions,
                selected: _pendingHowDiscovered,
                onToggle: (value, selected) =>
                    _toggle(_pendingHowDiscovered, value, selected),
                onSelectOnly: (value) => _selectOnly(
                  (next) => _pendingHowDiscovered = next,
                  value,
                ),
              ),
              const SizedBox(height: 20),
              _multiSelectRow(
                context: context,
                outlineBorder: outlineBorder,
                label: 'Rock type',
                description: 'Lithology recorded for the site.',
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
                const SizedBox(height: 20),
                SettingsFormStyles.settingsRow(
                  context: context,
                  label: 'Past routes',
                  description: 'Show completed aerial routes from the last 24h.',
                  controlWidth: 168,
                  control: SettingsFormStyles.densePopupField<bool>(
                    context: context,
                    outlineBorder: outlineBorder,
                    selectedChild: Text(
                      _pendingShowPastReconRoutes ? 'Show' : 'Hide',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    entries: [
                      DensePopupEntry(
                        value: false,
                        child: Text('Hide', style: theme.textTheme.bodyMedium),
                      ),
                      DensePopupEntry(
                        value: true,
                        child: Text('Show', style: theme.textTheme.bodyMedium),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == null) return;
                      setState(() => _pendingShowPastReconRoutes = value);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
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
                'Long-press an option in a multi-select menu to keep only that one.',
                style: SettingsFormStyles.finePrintStyle(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _multiSelectRow({
    required BuildContext context,
    required InputBorder outlineBorder,
    required String label,
    required String description,
    required List<String> options,
    required Set<String> selected,
    required void Function(String value, bool selected) onToggle,
    required void Function(String value) onSelectOnly,
  }) {
    final theme = Theme.of(context);
    return SettingsFormStyles.settingsRow(
      context: context,
      label: label,
      description: description,
      controlWidth: 168,
      control: SettingsFormStyles.multiSelectDensePopup(
        context: context,
        outlineBorder: outlineBorder,
        selectedChild: Text(
          SettingsFormStyles.multiSelectSummary(
            selectedCount: selected.length,
            totalCount: options.length,
          ),
          style: theme.textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
        entries: [
          for (final value in options)
            MultiSelectPopupEntry(
              value: value,
              label: siteFilterOptionLabel(value),
              selected: selected.contains(value),
            ),
        ],
        onToggle: onToggle,
        onSelectOnly: onSelectOnly,
      ),
    );
  }
}
