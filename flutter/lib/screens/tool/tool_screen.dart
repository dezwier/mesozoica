import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/tool_catalog_controller.dart';
import '../../models/tool.dart';
import '../../widgets/cards/tool_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/common/overlay_chrome_button.dart';
import '../../widgets/tools/filters/tool_filter_sheet.dart';
import '../../widgets/tools/tool_catalog_drawer.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = context.read<ToolCatalogController>();
    if (catalog.mode != ToolScreenMode.inventory) {
      catalog.setMode(ToolScreenMode.inventory);
    }
  }

  void _openFilterSheet(BuildContext context, ToolCatalogController catalog) {
    ToolFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      mode: ToolScreenMode.inventory,
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
      itemBuilder: (context, tool,
              {required isFocused, required fixedFaceHeight}) =>
          ToolTurnableCard(
            tool: tool,
            turnable: isFocused,
            fixedFaceHeight: fixedFaceHeight,
          ),
      emptyMessageBuilder: (context, catalog) {
        return catalog.hasActiveFilters
            ? 'No tools match these filters.'
            : 'No tools in your collection yet.';
      },
      floatingActionsBuilder: (context, catalog) {
        return [
          OverlayChromeButton(
            heroTag: 'tool_catalog_fab',
            tooltip: 'Catalog',
            icon: Icons.auto_stories_outlined,
            label: 'Catalog',
            onPressed: () => ToolCatalogDrawer.show(context),
          ),
          OverlayChromeButton(
            heroTag: 'tool_filter_fab',
            tooltip: 'Filter',
            icon: Icons.filter_list,
            label: 'Filter',
            showBadge: catalog.hasActiveFilters,
            onPressed: () => _openFilterSheet(context, catalog),
          ),
        ];
      },
    );
  }
}
