import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_controller.dart';
import '../../shell/map_chrome_insets.dart';
import '../../shell/shell_overlay_panel.dart';

/// Generic scroll/paginate/refresh host shared by the dino, fossil, site,
/// and tool catalog screens. Each screen supplies its card [itemBuilder],
/// empty-state copy, and floating actions (filter FABs, etc); this widget
/// owns the loading-more scroll listener and the loading/error/empty states
/// that were otherwise duplicated across those four screens.
class CatalogListScreen<C extends CatalogController<T>, T>
    extends StatefulWidget {
  const CatalogListScreen({
    super.key,
    this.isActive = true,
    required this.itemBuilder,
    required this.emptyMessageBuilder,
    this.isInitialLoading,
    this.floatingActionsBuilder,
  });

  final bool isActive;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String Function(BuildContext context, C catalog) emptyMessageBuilder;

  /// Full-screen spinner condition. Defaults to
  /// `catalog.loading && catalog.items.isEmpty`.
  final bool Function(C catalog)? isInitialLoading;

  final Widget Function(BuildContext context, C catalog)?
      floatingActionsBuilder;

  @override
  State<CatalogListScreen<C, T>> createState() =>
      CatalogListScreenState<C, T>();
}

class CatalogListScreenState<C extends CatalogController<T>, T>
    extends State<CatalogListScreen<C, T>> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<C>().refresh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (mounted) {
      context.read<C>().refresh();
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
        context.read<C>().loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<C>(
      builder: (context, catalog, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, catalog)),
            if (widget.isActive && widget.floatingActionsBuilder != null)
              Positioned(
                right: 12,
                bottom: MapChromeInsets.fabBottom(context),
                child: widget.floatingActionsBuilder!(context, catalog),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, C catalog) {
    final isInitialLoading = widget.isInitialLoading?.call(catalog) ??
        (catalog.loading && catalog.items.isEmpty);
    if (isInitialLoading) {
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
          widget.emptyMessageBuilder(context, catalog),
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

          return widget.itemBuilder(context, catalog.items[index]);
        },
      ),
    );
  }
}
