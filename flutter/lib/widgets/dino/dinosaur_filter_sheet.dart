import 'package:flutter/material.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../cards/geologic_timeline.dart';
import '../common/drawer_sheet_sizes.dart';
import '../profile/settings_form_styles.dart';

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
  late bool _pendingOnlyCustomImage;
  late bool _pendingOnlyLlmEnriched;

  @override
  void initState() {
    super.initState();
    _pendingSearch = widget.initialFilters.searchQuery;
    _searchController = TextEditingController(text: _pendingSearch);
    _pendingRange = RangeValues(
      widget.initialFilters.maYounger,
      widget.initialFilters.maOlder,
    );
    _pendingOnlyCustomImage = widget.initialFilters.onlyCustomImage;
    _pendingOnlyLlmEnriched = widget.initialFilters.onlyLlmEnriched;
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
      onlyCustomImage: _pendingOnlyCustomImage,
      onlyLlmEnriched: _pendingOnlyLlmEnriched,
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
      _pendingOnlyCustomImage = true;
      _pendingOnlyLlmEnriched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final outlineBorder = SettingsFormStyles.outlineBorder(context);
    final divisions =
        (GeologicTimeline.mesozoicOlderMa - GeologicTimeline.mesozoicYoungerMa)
            .round();

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
            SettingsFormStyles.settingsRow(
              context: context,
              label: 'Illustrated',
              description: 'Hide cards using the placeholder illustration.',
              controlWidth: 168,
              control: SettingsFormStyles.densePopupField<bool>(
                context: context,
                outlineBorder: outlineBorder,
                selectedChild: Text(
                  _pendingOnlyCustomImage ? 'Illustrated only' : 'All',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                entries: [
                  DensePopupEntry(
                    value: false,
                    child: Text('All', style: theme.textTheme.bodyMedium),
                  ),
                  DensePopupEntry(
                    value: true,
                    child: Text(
                      'Illustrated only',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == null) return;
                  _updatePending(() => _pendingOnlyCustomImage = value);
                },
              ),
            ),
            const SizedBox(height: 20),
            SettingsFormStyles.settingsRow(
              context: context,
              label: 'Enriched',
              description: 'Only show dinosaurs with LLM enrichment completed.',
              controlWidth: 168,
              control: SettingsFormStyles.densePopupField<bool>(
                context: context,
                outlineBorder: outlineBorder,
                selectedChild: Text(
                  _pendingOnlyLlmEnriched ? 'Enriched only' : 'All',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                entries: [
                  DensePopupEntry(
                    value: false,
                    child: Text('All', style: theme.textTheme.bodyMedium),
                  ),
                  DensePopupEntry(
                    value: true,
                    child: Text(
                      'Enriched only',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == null) return;
                  _updatePending(() => _pendingOnlyLlmEnriched = value);
                },
              ),
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
}
