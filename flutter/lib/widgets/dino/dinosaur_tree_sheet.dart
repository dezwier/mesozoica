import 'package:flutter/material.dart';

import '../common/chrome_fab.dart';
import '../common/drawer_sheet_sizes.dart';
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
      builder: (_) =>
          SizedBox(height: sheetHeight, child: const _DinosaurTreeSheetBody()),
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
                child: ChromeFab(
                  heroTag: 'tree_reset_fab',
                  tooltip: 'Reset view',
                  onPressed: () => _panelKey.currentState?.resetView(),
                  child: const Icon(Icons.center_focus_strong),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
