import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/phylo_tree_controller.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/dino/dinosaur_filter_sheet.dart';
import '../../widgets/tree/fractal_fern_view.dart';

class TreeScreen extends StatefulWidget {
  const TreeScreen({
    super.key,
    this.isActive = false,
  });

  final bool isActive;

  @override
  State<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends State<TreeScreen> {
  final GlobalKey<FractalFernViewState> _fernViewKey =
      GlobalKey<FractalFernViewState>();

  @override
  void initState() {
    super.initState();
    _loadIfActive();
  }

  @override
  void didUpdateWidget(covariant TreeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadIfActive();
  }

  void _loadIfActive() {
    if (!widget.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      context.read<PhyloTreeController>().loadIfNeeded();
    });
  }

  void _openFilterSheet(PhyloTreeController treeController) {
    DinosaurFilterSheet.show(
      context,
      initialFilters: treeController.filters,
      catalogTotal:
          treeController.totalGenera > 0 ? treeController.totalGenera : null,
      onApply: (filters) {
        treeController.applyFilters(filters);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhyloTreeController>(
      builder: (context, treeController, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, treeController)),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, PhyloTreeController treeController) {
    if (treeController.loading && !treeController.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (treeController.error != null && !treeController.loaded) {
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
                treeController.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: treeController.reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final layout = treeController.layout;
    if (layout == null || layout.root.children.isEmpty) {
      return Center(
        child: Text(
          treeController.hasActiveFilters
              ? 'No dinosaurs match these filters.'
              : 'No phylogeny data available yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FractalFernView(
            key: _fernViewKey,
            layout: layout,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'tree_reset_fab',
                tooltip: 'Reset view',
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                onPressed: () => _fernViewKey.currentState?.resetView(),
                child: const Icon(Icons.center_focus_strong),
              ),
              const SizedBox(height: 10),
              DinosaurFilterFab(
                heroTag: 'tree_filter_fab',
                hasActiveFilters: treeController.hasActiveFilters,
                onPressed: () => _openFilterSheet(treeController),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
