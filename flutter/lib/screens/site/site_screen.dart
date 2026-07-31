import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../widgets/cards/site_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/common/overlay_chrome_button.dart';
import '../../widgets/map/site_filter_sheet.dart';
import '../../widgets/site/site_catalog_drawer.dart';

class SiteScreen extends StatefulWidget {
  const SiteScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  State<SiteScreen> createState() => SiteScreenState();
}

class SiteScreenState extends State<SiteScreen> {
  final _listKey =
      GlobalKey<CatalogListScreenState<SiteCatalogController, SiteSummary>>();

  void scrollToTop() => _listKey.currentState?.scrollToTop();

  void _openFilterSheet(
    BuildContext context,
    SiteCatalogController catalog,
    bool isFieldMode,
  ) {
    final hasLocation =
        context.read<LocationService>().currentLocation != null;
    SiteFilterSheet.show(
      context,
      initialFilters: catalog.filters.copyWith(filterByStatus: isFieldMode),
      showStatusSection: isFieldMode,
      showSortSection: true,
      canSortByDistance: hasLocation,
      earliestDiscovery: catalog.earliestDiscovery,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFieldMode = context.watch<CatalogModeController>().isField;
    return CatalogListScreen<SiteCatalogController, SiteSummary>(
      key: _listKey,
      isActive: widget.isActive,
      isInitialLoading: (catalog) =>
          (catalog.loading || catalog.isLoadingMore) && catalog.items.isEmpty,
      itemBuilder: (context, site, {required isFocused, required fixedFaceHeight}) =>
          SiteTurnableCard(
            site: site,
            turnable: isFocused,
            fixedFaceHeight: fixedFaceHeight,
            onSiteUpdated: context.read<SiteCatalogController>().replaceSite,
          ),
      emptyMessageBuilder: (context, catalog) {
        final isField = context.watch<CatalogModeController>().isField;
        if (catalog.hasActiveFilters) return 'No sites match these filters.';
        return isField
            ? 'No linked field sites yet.'
            : 'No sites in the catalog yet.';
      },
      floatingActionsBuilder: (context, catalog) {
        return [
          OverlayChromeButton(
            heroTag: 'site_type_catalog_fab',
            tooltip: 'Catalog',
            icon: Icons.auto_stories_outlined,
            label: 'Catalog',
            onPressed: () => SiteCatalogDrawer.show(context),
          ),
          OverlayChromeButton(
            heroTag: 'site_catalog_filter_fab',
            tooltip: 'Filter',
            icon: Icons.filter_list,
            label: 'Filter',
            showBadge: catalog.hasActiveFilters,
            onPressed: () => _openFilterSheet(context, catalog, isFieldMode),
          ),
        ];
      },
    );
  }
}
