import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/phylo_tree_controller.dart';
import '../../models/dinosaur.dart';
import '../../widgets/cards/dinosaur_turnable_card.dart';
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
  DinosaurSummary? _selectedDinosaur;

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

  void _onGenusTap(DinosaurSummary dinosaur) {
    setState(() => _selectedDinosaur = dinosaur);
  }

  void _dismissCard() {
    setState(() => _selectedDinosaur = null);
  }

  void _openFilterSheet(PhyloTreeController treeController) {
    DinosaurFilterSheet.show(
      context,
      initialFilters: treeController.filters,
      catalogTotal:
          treeController.totalGenera > 0 ? treeController.totalGenera : null,
      onApply: (filters) {
        setState(() => _selectedDinosaur = null);
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
            if (_selectedDinosaur != null)
              _DinosaurCardOverlay(
                dinosaur: _selectedDinosaur!,
                onDismiss: _dismissCard,
              ),
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
            layout: layout,
            onGenusTap: _onGenusTap,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: DinosaurFilterFab(
            heroTag: 'tree_filter_fab',
            hasActiveFilters: treeController.hasActiveFilters,
            onPressed: () => _openFilterSheet(treeController),
          ),
        ),
      ],
    );
  }
}

class _DinosaurCardOverlay extends StatelessWidget {
  const _DinosaurCardOverlay({
    required this.dinosaur,
    required this.onDismiss,
  });

  final DinosaurSummary dinosaur;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: GestureDetector(
          onTap: onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: DinosaurTurnableCard(dinosaur: dinosaur),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
