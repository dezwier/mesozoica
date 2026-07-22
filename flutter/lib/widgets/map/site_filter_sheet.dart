import 'package:flutter/material.dart';

import '../../models/site_map_filters.dart';
import '../common/drawer_sheet_sizes.dart';

class SiteFilterSheet extends StatefulWidget {
  const SiteFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
    this.showStatusSection = true,
  });

  final SiteMapFilters initialFilters;
  final ValueChanged<SiteMapFilters> onApply;
  final bool showStatusSection;

  static Future<void> show(
    BuildContext context, {
    required SiteMapFilters initialFilters,
    required ValueChanged<SiteMapFilters> onApply,
    bool showStatusSection = true,
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
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _pendingStatuses = {...widget.initialFilters.statuses};
    _pendingPeriods = {...widget.initialFilters.periods};
    _pendingRockTypes = {...widget.initialFilters.rockTypes};
  }

  void _commitPending() {
    if (_applied) return;
    _applied = true;
    widget.onApply(
      SiteMapFilters(
        statuses: _pendingStatuses,
        periods: _pendingPeriods,
        rockTypes: _pendingRockTypes,
        filterByStatus: widget.showStatusSection,
      ),
    );
  }

  SiteMapFilters _buildPendingFilters() {
    return SiteMapFilters(
      statuses: _pendingStatuses,
      periods: _pendingPeriods,
      rockTypes: _pendingRockTypes,
      filterByStatus: widget.showStatusSection,
    );
  }

  void _clearPending() {
    setState(() {
      _pendingStatuses = {...siteStatusOptions};
      _pendingPeriods = {...sitePeriodOptions};
      _pendingRockTypes = {...siteRockTypeOptions};
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
