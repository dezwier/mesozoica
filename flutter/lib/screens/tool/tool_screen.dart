import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/tool_catalog_controller.dart';
import '../../widgets/cards/tool_turnable_card.dart';
import '../../widgets/tool/tool_filter_fab.dart';
import '../../widgets/tool/tool_filter_sheet.dart';

class ToolScreen extends StatefulWidget {
  const ToolScreen({
    super.key,
    this.isActive = true,
    this.onScrollUpdate,
  });

  final bool isActive;
  final void Function(double offset, double delta)? onScrollUpdate;

  @override
  State<ToolScreen> createState() => ToolScreenState();
}

class ToolScreenState extends State<ToolScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounceTimer;
  double? _previousScrollOffset;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ToolCatalogController>().refresh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (mounted) {
      context.read<ToolCatalogController>().refresh();
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

  double get scrollOffset =>
      _scrollController.hasClients ? _scrollController.offset : 0;

  void _onScroll() {
    if (_scrollController.hasClients &&
        widget.isActive &&
        widget.onScrollUpdate != null) {
      final offset = _scrollController.offset;
      final previous = _previousScrollOffset ?? offset;
      widget.onScrollUpdate!(offset, offset - previous);
      _previousScrollOffset = offset;
    }

    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent * 0.8) {
        context.read<ToolCatalogController>().loadMore();
      }
    });
  }

  void _openFilterSheet(ToolCatalogController catalog) {
    ToolFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ToolCatalogController>(
      builder: (context, catalog, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, catalog)),
            if (widget.isActive)
              Positioned(
                right: 12,
                bottom: 12,
                child: ToolFilterFab(
                  hasActiveFilters: catalog.hasActiveFilters,
                  onPressed: () => _openFilterSheet(catalog),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ToolCatalogController catalog) {
    if (catalog.loading && catalog.items.isEmpty) {
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
      return Center(
        child: Text(
          catalog.hasActiveFilters
              ? 'No tools match these filters.'
              : 'No tools in the catalog yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: catalog.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        itemCount: catalog.items.length + (catalog.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= catalog.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final tool = catalog.items[index];
          return ToolTurnableCard(tool: tool);
        },
      ),
    );
  }
}
