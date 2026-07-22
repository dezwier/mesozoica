import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/fossil_catalog_controller.dart';
import '../../models/fossil.dart';
import '../../widgets/cards/fossil_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/fossil/fossil_filter_fab.dart';
import '../../widgets/fossil/fossil_filter_sheet.dart';

class FossilScreen extends StatefulWidget {
  const FossilScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  State<FossilScreen> createState() => FossilScreenState();
}

class FossilScreenState extends State<FossilScreen> {
  final _listKey = GlobalKey<
      CatalogListScreenState<FossilCatalogController, FossilSummary>>();

  void scrollToTop() => _listKey.currentState?.scrollToTop();

  void _openFilterSheet(
    BuildContext context,
    FossilCatalogController catalog,
  ) {
    final isField = context.read<CatalogModeController>().isField;
    FossilFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      showLlmEnrichedFilter: !isField,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogListScreen<FossilCatalogController, FossilSummary>(
      key: _listKey,
      isActive: widget.isActive,
      itemBuilder: (context, fossil) => FossilTurnableCard(fossil: fossil),
      emptyMessageBuilder: (context, catalog) => catalog.hasActiveFilters
          ? 'No fossils match these filters.'
          : 'No fossils in the catalog yet.',
      floatingActionsBuilder: (context, catalog) => FossilFilterFab(
        hasActiveFilters: catalog.hasActiveFilters,
        onPressed: () => _openFilterSheet(context, catalog),
      ),
    );
  }
}
