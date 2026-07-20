import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/phylo_tree_controller.dart';
import '../common/drawer_sheet_sizes.dart';
import 'dinosaur_filter_fab.dart';
import 'dinosaur_filter_sheet.dart';
import '../tree/phylo_tree_panel.dart';

class DinosaurTreeSheet {
  DinosaurTreeSheet._();

  static Future<void> show(BuildContext context) {
    final sheetHeight =
        MediaQuery.sizeOf(context).height * DrawerSheetSizes.initialChildSize;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: sheetHeight,
        child: const _DinosaurTreeSheetBody(),
      ),
    );
  }
}

class _DinosaurTreeSheetBody extends StatefulWidget {
  const _DinosaurTreeSheetBody();

  @override
  State<_DinosaurTreeSheetBody> createState() => _DinosaurTreeSheetBodyState();
}

class _DinosaurTreeSheetBodyState extends State<_DinosaurTreeSheetBody> {
  final _panelKey = GlobalKey<PhyloTreePanelState>();

  void _openFilterSheet(PhyloTreeController treeController) {
    DinosaurFilterSheet.show(
      context,
      initialFilters: treeController.filters,
      catalogTotal:
          treeController.totalGenera > 0 ? treeController.totalGenera : null,
      onApply: treeController.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Cladogram Tree',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        Expanded(
          child: Stack(
            children: [
              PhyloTreePanel(key: _panelKey),
              Positioned(
                top: 8,
                right: 12,
                child: Consumer<PhyloTreeController>(
                  builder: (context, treeController, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'tree_reset_fab',
                          tooltip: 'Reset view',
                          backgroundColor: Theme.of(context)
                              .floatingActionButtonTheme
                              .backgroundColor,
                          foregroundColor: Theme.of(context)
                              .floatingActionButtonTheme
                              .foregroundColor,
                          onPressed: () =>
                              _panelKey.currentState?.resetView(),
                          child: const Icon(Icons.center_focus_strong),
                        ),
                        const SizedBox(width: 10),
                        DinosaurFilterFab(
                          heroTag: 'tree_filter_fab',
                          hasActiveFilters: treeController.hasActiveFilters,
                          onPressed: () => _openFilterSheet(treeController),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
