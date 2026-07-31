import 'package:flutter/material.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../utils/display_text.dart';
import '../cards/geologic_timeline.dart';
import '../common/drawer_sheet_sizes.dart';
import '../profile/settings_form_styles.dart';

String dinosaurDietFilterLabel(String value) =>
    toTitleCase(value.replaceAll('-', ' '));

class DinosaurFilterSheet extends StatefulWidget {
  const DinosaurFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onPendingChanged,
    this.catalogTotal,
  });

  final DinosaurCatalogFilters initialFilters;
  final ValueChanged<DinosaurCatalogFilters> onPendingChanged;
  final int? catalogTotal;

  static Future<void> show(
    BuildContext context, {
    required DinosaurCatalogFilters initialFilters,
    required ValueChanged<DinosaurCatalogFilters> onApply,
    int? catalogTotal,
  }) async {
    var pending = initialFilters;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DinosaurFilterSheet(
        initialFilters: initialFilters,
        catalogTotal: catalogTotal,
        onPendingChanged: (filters) => pending = filters,
      ),
    );
    onApply(pending);
  }

  @override
  State<DinosaurFilterSheet> createState() => _DinosaurFilterSheetState();
}

class _DinosaurFilterSheetState extends State<DinosaurFilterSheet> {
  late final TextEditingController _searchController;
  late String _pendingSearch;
  late RangeValues _pendingRange;
  late Set<String> _pendingDiets;
  late RangeValues _pendingLengthM;
  late RangeValues _pendingMassT;

  @override
  void initState() {
    super.initState();
    _pendingSearch = widget.initialFilters.searchQuery;
    _searchController = TextEditingController(text: _pendingSearch);
    _pendingRange = RangeValues(
      widget.initialFilters.maYounger,
      widget.initialFilters.maOlder,
    );
    _pendingDiets = Set<String>.from(widget.initialFilters.diets);
    _pendingLengthM = RangeValues(
      widget.initialFilters.lengthMMin,
      widget.initialFilters.lengthMMax,
    );
    _pendingMassT = RangeValues(
      widget.initialFilters.massTMin,
      widget.initialFilters.massTMax,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DinosaurCatalogFilters _buildPendingFilters() {
    return DinosaurCatalogFilters(
      searchQuery: _pendingSearch.trim(),
      maYounger: _pendingRange.start,
      maOlder: _pendingRange.end,
      diets: Set<String>.from(_pendingDiets),
      lengthMMin: _pendingLengthM.start,
      lengthMMax: _pendingLengthM.end,
      massKgMin: _pendingMassT.start * 1000.0,
      massKgMax: _pendingMassT.end * 1000.0,
    );
  }

  void _updatePending(VoidCallback update) {
    setState(update);
    widget.onPendingChanged(_buildPendingFilters());
  }

  void _clearPending() {
    _updatePending(() {
      _pendingSearch = '';
      _searchController.clear();
      _pendingRange = const RangeValues(
        GeologicTimeline.mesozoicYoungerMa,
        GeologicTimeline.mesozoicOlderMa,
      );
      _pendingDiets = {};
      _pendingLengthM = const RangeValues(lengthMMinBound, lengthMMaxBound);
      _pendingMassT = const RangeValues(massTMinBound, massTMaxBound);
    });
  }

  void _toggleDiet(String value, bool selected) {
    _updatePending(() {
      if (selected) {
        _pendingDiets.add(value);
      } else {
        _pendingDiets.remove(value);
      }
    });
  }

  void _selectOnlyDiet(String value) {
    _updatePending(() => _pendingDiets = {value});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final outlineBorder = SettingsFormStyles.outlineBorder(context);
    final divisions =
        (GeologicTimeline.mesozoicOlderMa - GeologicTimeline.mesozoicYoungerMa)
            .round();
    final lengthDivisions = (lengthMMaxBound - lengthMMinBound).round();
    final massDivisions = (massTMaxBound - massTMinBound).round();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: DrawerSheetSizes.initialChildSize,
      minChildSize: DrawerSheetSizes.minChildSize,
      maxChildSize: DrawerSheetSizes.maxChildSize,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.catalogTotal != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${widget.catalogTotal} dinosaurs in catalog',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _buildSearchField(context),
            const SizedBox(height: 20),
            _multiSelectRow(
              context: context,
              outlineBorder: outlineBorder,
              label: 'Diet',
              description: 'Feeding habit of the dinosaur.',
              options: dinosaurDietFilterOptions,
              selected: _pendingDiets,
              onToggle: _toggleDiet,
              onSelectOnly: _selectOnlyDiet,
            ),
            const SizedBox(height: 20),
            Text(
              'Length',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Showing ${_formatMeters(_pendingLengthM.start)} – '
              '${_formatMeters(_pendingLengthM.end)} m',
              style: SettingsFormStyles.finePrintStyle(context),
            ),
            RangeSlider(
              values: _pendingLengthM,
              min: lengthMMinBound,
              max: lengthMMaxBound,
              divisions: lengthDivisions,
              onChanged: (values) {
                _updatePending(() => _pendingLengthM = values);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${lengthMMinBound.round()} m',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${lengthMMaxBound.round()} m',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Mass',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Showing ${_formatTonnes(_pendingMassT.start)} – '
              '${_formatTonnes(_pendingMassT.end)} t',
              style: SettingsFormStyles.finePrintStyle(context),
            ),
            RangeSlider(
              values: _pendingMassT,
              min: massTMinBound,
              max: massTMaxBound,
              divisions: massDivisions,
              onChanged: (values) {
                _updatePending(() => _pendingMassT = values);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${massTMinBound.round()} t',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${massTMaxBound.round()} t',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Time range',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Showing ${_pendingRange.end.round()} – ${_pendingRange.start.round()} Ma',
              style: SettingsFormStyles.finePrintStyle(context),
            ),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
              child: RangeSlider(
                values: _pendingRange,
                min: GeologicTimeline.mesozoicYoungerMa,
                max: GeologicTimeline.mesozoicOlderMa,
                divisions: divisions,
                onChanged: (values) {
                  _updatePending(() => _pendingRange = values);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${GeologicTimeline.mesozoicOlderMa.round()} Ma',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${GeologicTimeline.mesozoicYoungerMa.round()} Ma',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        );
      },
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
              label: dinosaurDietFilterLabel(value),
              selected: selected.contains(value),
            ),
        ],
        onToggle: onToggle,
        onSelectOnly: onSelectOnly,
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: (value) {
          _updatePending(() => _pendingSearch = value);
        },
        decoration: InputDecoration(
          hintText: 'Search dinosaurs…',
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _updatePending(() => _pendingSearch = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  String _formatMeters(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toStringAsFixed(1);
  }

  String _formatTonnes(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toStringAsFixed(1);
  }
}
