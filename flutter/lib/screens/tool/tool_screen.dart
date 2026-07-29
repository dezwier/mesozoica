import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../widgets/cards/tool_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/common/chrome_fab.dart';
import '../../widgets/tool/tool_filter_fab.dart';
import '../../widgets/tool/tool_filter_sheet.dart';

class ToolScreen extends StatefulWidget {
  const ToolScreen({super.key, this.isActive = true});

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
      emptyMessageBuilder: (context, catalog) {
        if (catalog.mode == ToolScreenMode.catalog) {
          return catalog.hasActiveFilters
              ? 'No tools match these filters.'
              : 'No tools in the catalog yet.';
        }
        return catalog.hasActiveFilters
            ? 'No tools match these filters.'
            : 'No tools in your collection yet.';
      },
      floatingActionsBuilder: (context, catalog) {
        final isAdmin =
            context.read<AuthController>().currentUser?.isAdmin ?? false;
        final mode = catalog.mode;
        final nextMode = mode == ToolScreenMode.catalog
            ? ToolScreenMode.inventory
            : ToolScreenMode.catalog;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin) ...[
              ChromeFab(
                heroTag: 'tool_mode_fab',
                // Match the existing filter FAB tone so the UI feels consistent.
                tone: ChromeFabTone.warm,
                tooltip: mode == ToolScreenMode.catalog
                    ? 'Switch to Inventory'
                    : 'Switch to Catalog',
                active: mode == ToolScreenMode.catalog,
                onPressed: () => catalog.setMode(nextMode, isAdmin: isAdmin),
                child: Icon(
                  mode == ToolScreenMode.catalog
                      ? Icons.inventory_2_outlined
                      : Icons.auto_stories_outlined,
                ),
              ),
            ],
            ToolFilterFab(
              hasActiveFilters: catalog.hasActiveFilters,
              onPressed: () => _openFilterSheet(context, catalog),
            ),
          ],
        );
      },
    );
  }
}
