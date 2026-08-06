import 'package:flutter/material.dart';

import '../../controllers/fossil_catalog_controller.dart';
import '../cards/geologic_timeline.dart';
import '../common/drawer_sheet_sizes.dart';
import '../profile/settings_form_styles.dart';

class FossilFilterSheet extends StatefulWidget {
  const FossilFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onPendingChanged,
    this.catalogTotal,
    this.showLlmEnrichedFilter = true,
  });

  final FossilCatalogFilters initialFilters;
  final ValueChanged<FossilCatalogFilters> onPendingChanged;
  final int? catalogTotal;
  final bool showLlmEnrichedFilter;

  static Future<void> show(
    BuildContext context, {
    required FossilCatalogFilters initialFilters,
    required ValueChanged<FossilCatalogFilters> onApply,
    int? catalogTotal,
    bool showLlmEnrichedFilter = true,
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
      builder: (_) => FossilFilterSheet(
        initialFilters: initialFilters,
        catalogTotal: catalogTotal,
        showLlmEnrichedFilter: showLlmEnrichedFilter,
        onPendingChanged: (filters) => pending = filters,
      ),
    );
    onApply(pending);
  }

  @override
  State<FossilFilterSheet> createState() => _FossilFilterSheetState();
}

class _FossilFilterSheetState extends State<FossilFilterSheet> {
  late final TextEditingController _dinoSearchController;
  late final TextEditingController _fossilSearchController;
  late String _pendingDinoSearch;
  late String _pendingFossilSearch;
  late RangeValues _pendingRange;
  late bool _pendingOnlyCustomFossilImage;
  late bool _pendingOnlyLlmEnriched;

  @override
  void initState() {
    super.initState();
    _pendingDinoSearch = widget.initialFilters.dinoSearchQuery;
    _pendingFossilSearch = widget.initialFilters.fossilSearchQuery;
    _dinoSearchController = TextEditingController(text: _pendingDinoSearch);
    _fossilSearchController = TextEditingController(text: _pendingFossilSearch);
    _pendingRange = RangeValues(
      widget.initialFilters.maYounger,
      widget.initialFilters.maOlder,
    );
    _pendingOnlyCustomFossilImage = widget.initialFilters.onlyCustomFossilImage;
    _pendingOnlyLlmEnriched = widget.initialFilters.onlyLlmEnriched;
  }

  @override
  void dispose() {
    _dinoSearchController.dispose();
    _fossilSearchController.dispose();
    super.dispose();
  }

  FossilCatalogFilters _buildPendingFilters() {
    return FossilCatalogFilters(
      dinoSearchQuery: _pendingDinoSearch.trim(),
      fossilSearchQuery: _pendingFossilSearch.trim(),
      maYounger: _pendingRange.start,
      maOlder: _pendingRange.end,
      onlyCustomFossilImage: _pendingOnlyCustomFossilImage,
      onlyLlmEnriched: _pendingOnlyLlmEnriched,
    );
  }

  void _updatePending(VoidCallback update) {
    setState(update);
    widget.onPendingChanged(_buildPendingFilters());
  }

  void _clearPending() {
    _updatePending(() {
      _pendingDinoSearch = '';
      _pendingFossilSearch = '';
      _dinoSearchController.clear();
      _fossilSearchController.clear();
      _pendingRange = const RangeValues(
        GeologicTimeline.mesozoicYoungerMa,
        GeologicTimeline.mesozoicOlderMa,
      );
      _pendingOnlyCustomFossilImage = false;
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
                  '${widget.catalogTotal} fossils in catalog',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _buildSearchField(
              context,
              controller: _dinoSearchController,
              hintText: 'Search dinosaur name…',
              onChanged: (value) {
                _updatePending(() => _pendingDinoSearch = value);
              },
              onClear: () {
                _dinoSearchController.clear();
                _updatePending(() => _pendingDinoSearch = '');
              },
            ),
            const SizedBox(height: 12),
            _buildSearchField(
              context,
              controller: _fossilSearchController,
              hintText: 'Search fossil name…',
              onChanged: (value) {
                _updatePending(() => _pendingFossilSearch = value);
              },
              onClear: () {
                _fossilSearchController.clear();
                _updatePending(() => _pendingFossilSearch = '');
              },
            ),
            const SizedBox(height: 20),
            SettingsFormStyles.settingsRow(
              context: context,
              label: 'Illustrated',
              description: 'Only show fossils with a curated card image.',
              controlWidth: 168,
              control: SettingsFormStyles.densePopupField<bool>(
                context: context,
                outlineBorder: outlineBorder,
                selectedChild: Text(
                  _pendingOnlyCustomFossilImage ? 'Illustrated only' : 'All',
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
                  _updatePending(() => _pendingOnlyCustomFossilImage = value);
                },
              ),
            ),
            if (widget.showLlmEnrichedFilter) ...[
              const SizedBox(height: 20),
              SettingsFormStyles.settingsRow(
                context: context,
                label: 'Enriched',
                description: 'Only show fossils with LLM enrichment completed.',
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
            ],
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

  Widget _buildSearchField(
    BuildContext context, {
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: onClear,
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
