import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../shell/map_chrome_insets.dart';
import '../../shell/shell_overlay_panel.dart';
import '../../widgets/cards/site_turnable_card.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/map/site_filter_sheet.dart';

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
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SiteCatalogController>().refresh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (mounted) {
      context.read<SiteCatalogController>().refresh();
    }
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onScroll() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent * 0.8) {
        context.read<SiteCatalogController>().loadMore();
      }
    });
  }

  void _openFilterSheet(SiteCatalogController catalog, bool isFieldMode) {
    SiteFilterSheet.show(
      context,
      initialFilters: catalog.filters.copyWith(filterByStatus: isFieldMode),
      showStatusSection: isFieldMode,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFieldMode = context.watch<CatalogModeController>().isField;
    return Consumer<SiteCatalogController>(
      builder: (context, catalog, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, catalog)),
            if (widget.isActive)
              Positioned(
                right: 12,
                bottom: MapChromeInsets.fabBottom(context),
                child: DinosaurFilterFab(
                  heroTag: 'site_catalog_filter_fab',
                  hasActiveFilters: catalog.hasActiveFilters,
                  onPressed: () => _openFilterSheet(catalog, isFieldMode),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SiteCatalogController catalog) {
    if ((catalog.loading || catalog.isLoadingMore) && catalog.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (catalog.error != null && catalog.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                catalog.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => catalog.refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (catalog.isEmpty) {
      final isField = context.watch<CatalogModeController>().isField;
      return Center(
        child: Text(
          catalog.hasActiveFilters
              ? 'No sites match these filters.'
              : isField
                  ? 'No linked field sites yet.'
                  : 'No sites in the catalog yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: catalog.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: 8,
          bottom: ShellOverlayPanel.contentBottomInset(context),
        ),
        itemCount: catalog.items.length + (catalog.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= catalog.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final site = catalog.items[index];
          return SiteTurnableCard(
            site: site,
            onSiteUpdated: catalog.replaceSite,
          );
        },
      ),
    );
  }
}
