import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/phylo_tree_controller.dart';
import 'fractal_fern_view.dart';

class PhyloTreePanel extends StatefulWidget {
  const PhyloTreePanel({super.key});

  @override
  State<PhyloTreePanel> createState() => PhyloTreePanelState();
}

class PhyloTreePanelState extends State<PhyloTreePanel> {
  final GlobalKey<FractalFernViewState> _fernViewKey =
      GlobalKey<FractalFernViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PhyloTreeController>().loadIfNeeded();
    });
  }

  void resetView() {
    _fernViewKey.currentState?.resetView();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PhyloTreeController>(
      builder: (context, treeController, _) => _buildBody(context, treeController),
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

    return FractalFernView(
      key: _fernViewKey,
      layout: layout,
    );
  }
}
