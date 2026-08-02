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
    this.showDiscoveryTimeSection = true,
    this.showHowDiscoveredSection = true,
    this.canSortByDistance = true,
    this.earliestDiscovery,
  });

  final SiteMapFilters initialFilters;
  final ValueChanged<SiteMapFilters> onApply;
  final bool showStatusSection;
  final bool showReconRoutesSection;

  /// Inventory-only: Nearest / Discovered sorts.
  final bool showSortSection;

  /// Inventory/map-only: discovery-day range.
  final bool showDiscoveryTimeSection;

  /// Inventory/map-only: how the site was found.
  final bool showHowDiscoveredSection;

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
    bool showDiscoveryTimeSection = true,
    bool showHowDiscoveredSection = true,
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
        showDiscoveryTimeSection: showDiscoveryTimeSection,
        showHowDiscoveredSection: showHowDiscoveredSection,
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
  /// Calendar days from earliest → today. `0` = same day (no range slider).
  late final int _dayCount;
  late final bool _hasDiscoveryDates;
  bool _applied = false;

  static final _dayLabel = DateFormat('MMM d, yyyy');

  bool get _canSlideDiscoveryDays =>
      _hasDiscoveryDates && _dayCount >= 1;

  @override
  void initState() {
    super.initState();
    _hasDiscoveryDates = widget.earliestDiscovery != null;
    final bounds = discoveryTimeWindowBounds(
      earliestDiscovery: widget.earliestDiscovery,
    );
    _windowStart = bounds.start;
    _windowEnd = bounds.end;
    _dayCount = discoveryTimeNaturalDaySpan(
      earliestDiscovery: widget.earliestDiscovery,
    );
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
    if (!_canSlideDiscoveryDays) return const RangeValues(0, 0);
    // Unbound filter = full window (do not map start/end dates to day 0/0).
    if (filters.discoveredAfter == null && filters.discoveredBefore == null) {
      return RangeValues(0, _dayCount.toDouble());
    }
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
      !_canSlideDiscoveryDays ||
      (_pendingDiscoveryDays.start <= 0.001 &&
          _pendingDiscoveryDays.end >= _dayCount - 0.001);

  SiteMapFilters _buildPendingFilters() {
    final after = !widget.showDiscoveryTimeSection
        ? widget.initialFilters.discoveredAfter
        : (_discoveryTimeIsFullSpan
            ? null
            : _dateAtDay(_pendingDiscoveryDays.start));
    final before = !widget.showDiscoveryTimeSection
        ? widget.initialFilters.discoveredBefore
        : (_discoveryTimeIsFullSpan
            ? null
            : _dateAtDay(_pendingDiscoveryDays.end)
                .add(const Duration(hours: 23, minutes: 59, seconds: 59)));
    return SiteMapFilters(
      statuses: widget.showStatusSection
          ? _pendingStatuses
          : widget.initialFilters.statuses,
      periods: _pendingPeriods,
      rockTypes: _pendingRockTypes,
      howDiscovered: widget.showHowDiscoveredSection
          ? _pendingHowDiscovered
          : widget.initialFilters.howDiscovered,
      discoveredAfter: after,
      discoveredBefore: before,
      sort: widget.showSortSection
          ? _pendingSort
          : widget.initialFilters.sort,
      filterByStatus: widget.showStatusSection
          ? true
          : widget.initialFilters.filterByStatus,
      showPastAerialRoutes: widget.showReconRoutesSection
          ? _pendingShowPastReconRoutes
          : widget.initialFilters.showPastAerialRoutes,
    );
  }

  void _commitPending() {
    if (_applied) return;
    _applied = true;
    widget.onApply(_buildPendingFilters());
  }

  void _clearPending() {
    setState(() {
      if (widget.showStatusSection) {
        _pendingStatuses = {...siteStatusOptions};
      }
      _pendingPeriods = {...sitePeriodOptions};
      _pendingRockTypes = {...siteRockTypeOptions};
      if (widget.showHowDiscoveredSection) {
        _pendingHowDiscovered = {...siteHowDiscoveredOptions};
      }
      if (widget.showDiscoveryTimeSection) {
        _pendingDiscoveryDays = RangeValues(0, _dayCount.toDouble());
      }
      if (widget.showSortSection) {
        _pendingSort = widget.canSortByDistance
            ? SiteCatalogSort.distance
            : SiteCatalogSort.discoveredAtDesc;
      }
      if (widget.showReconRoutesSection) {
        _pendingShowPastReconRoutes = true;
      }
    });
  }

  bool get _clearEnabled {
    final pending = _buildPendingFilters();
    if (!widget.showSortSection &&
        !widget.showStatusSection &&
        !widget.showDiscoveryTimeSection &&
        !widget.showHowDiscoveredSection) {
      return pending.hasActiveCatalogFilters;
    }
    return pending.hasActiveFilters;
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
    final date = _dateAtDay(day);
    if (!date.isBefore(_windowEnd)) return 'Today';
    return _dayLabel.format(date.toLocal());
  }

  String _formatWindowDay(DateTime day) {
    final date = discoveryDateOnlyUtc(day);
    if (!date.isBefore(_windowEnd)) return 'Today';
    return _dayLabel.format(date.toLocal());
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _chapterHeader(theme, 'Excavation Sites'),
              if (widget.showSortSection) ...[
                const SizedBox(height: 16),
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
              if (widget.showDiscoveryTimeSection) ...[
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
                if (!_hasDiscoveryDates)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No discovery dates on current sites yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (!_canSlideDiscoveryDays)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'All current sites were discovered on '
                      '${_formatWindowDay(_windowStart)}.',
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
                    divisions: _dayCount,
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
              if (widget.showHowDiscoveredSection) ...[
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
              ],
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
                const SizedBox(height: 28),
                _chapterHeader(theme, 'Map overlays'),
                const SizedBox(height: 16),
                SettingsFormStyles.settingsRow(
                  context: context,
                  label: 'Past routes',
                  description:
                      'Show completed aerial routes from the last 24h.',
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
                    onPressed: _clearEnabled ? _clearPending : null,
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
            ],
          );
        },
      ),
    );
  }

  Widget _chapterHeader(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.2,
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
