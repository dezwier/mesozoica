import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../widgets/cards/dinosaur_turnable_card.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/dino/dinosaur_filter_sheet.dart';

class DinoScreen extends StatefulWidget {
  const DinoScreen({super.key});

  @override
  State<DinoScreen> createState() => _DinoScreenState();
}

class _DinoScreenState extends State<DinoScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DinosaurCatalogController>().refresh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (mounted) {
      context.read<DinosaurCatalogController>().refresh();
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

  void _onScroll() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent * 0.8) {
        context.read<DinosaurCatalogController>().loadMore();
      }
    });
  }

  void _openFilterSheet(DinosaurCatalogController catalog) {
    DinosaurFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DinosaurCatalogController>(
      builder: (context, catalog, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, catalog)),
            Positioned(
              right: 12,
              bottom: 12,
              child: DinosaurFilterFab(
                hasActiveFilters: catalog.hasActiveFilters,
                onPressed: () => _openFilterSheet(catalog),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, DinosaurCatalogController catalog) {
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
              ? 'No dinosaurs match these filters.'
              : 'No dinosaurs in the catalog yet.',
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

          final dinosaur = catalog.items[index];
          return DinosaurTurnableCard(dinosaur: dinosaur);
        },
      ),
    );
  }
}
