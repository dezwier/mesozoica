import 'package:flutter/material.dart';

import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../widgets/cards/tool_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/tool/tool_filter_fab.dart';
import '../../widgets/tool/tool_filter_sheet.dart';

class ToolScreen extends StatefulWidget {
  const ToolScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  State<ToolScreen> createState() => ToolScreenState();
}

class ToolScreenState extends State<ToolScreen> {
  final _listKey =
      GlobalKey<CatalogListScreenState<ToolCatalogController, ToolSummary>>();

  void scrollToTop() => _listKey.currentState?.scrollToTop();

  void _openFilterSheet(BuildContext context, ToolCatalogController catalog) {
    ToolFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      availableCategories: catalog.availableCategories,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogListScreen<ToolCatalogController, ToolSummary>(
      key: _listKey,
      isActive: widget.isActive,
      itemBuilder: (context, tool) => ToolTurnableCard(tool: tool),
      emptyMessageBuilder: (context, catalog) => catalog.hasActiveFilters
          ? 'No tools match these filters.'
          : 'No tools in the catalog yet.',
      floatingActionsBuilder: (context, catalog) => ToolFilterFab(
        hasActiveFilters: catalog.hasActiveFilters,
        onPressed: () => _openFilterSheet(context, catalog),
      ),
    );
  }
}
