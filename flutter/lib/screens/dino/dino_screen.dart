import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../models/dinosaur.dart';
import '../../widgets/cards/dinosaur_turnable_card.dart';
import '../../widgets/common/catalog_list_screen.dart';
import '../../widgets/common/chrome_fab.dart';
import '../../widgets/dino/dinosaur_catalog_drawer.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/dino/dinosaur_filter_sheet.dart';
import '../../widgets/dino/dinosaur_tree_sheet.dart';

class DinoScreen extends StatefulWidget {
  const DinoScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  State<DinoScreen> createState() => DinoScreenState();
}

class DinoScreenState extends State<DinoScreen> {
  final _listKey = GlobalKey<
      CatalogListScreenState<DinosaurCatalogController, DinosaurSummary>>();

  void scrollToTop() => _listKey.currentState?.scrollToTop();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = context.read<DinosaurCatalogController>();
    if (catalog.mode != DinoScreenMode.inventory) {
      catalog.setMode(DinoScreenMode.inventory);
    }
  }

  void _openFilterSheet(
    BuildContext context,
    DinosaurCatalogController catalog,
  ) {
    DinosaurFilterSheet.show(
      context,
      initialFilters: catalog.filters,
      catalogTotal: catalog.total > 0 ? catalog.total : null,
      onApply: catalog.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogListScreen<DinosaurCatalogController, DinosaurSummary>(
      key: _listKey,
      isActive: widget.isActive,
      itemBuilder: (context, dinosaur,
              {required isFocused, required fixedFaceHeight}) =>
          DinosaurTurnableCard(
            dinosaur: dinosaur,
            turnable: isFocused,
            fixedFaceHeight: fixedFaceHeight,
          ),
      emptyMessageBuilder: (context, catalog) {
        return catalog.hasActiveFilters
            ? 'No dinosaurs match these filters.'
            : 'No dinosaurs in your collection yet.';
      },
      floatingActionsBuilder: (context, catalog) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ChromeFab(
              heroTag: 'dino_catalog_fab',
              tone: ChromeFabTone.warm,
              tooltip: 'Catalog',
              onPressed: () => DinosaurCatalogDrawer.show(context),
              child: const Icon(Icons.auto_stories_outlined),
            ),
            ChromeFab(
              heroTag: 'dino_tree_fab',
              tooltip: 'Phylogeny',
              onPressed: () => DinosaurTreeSheet.show(context),
              child: const Icon(Icons.account_tree),
            ),
            DinosaurFilterFab(
              hasActiveFilters: catalog.hasActiveFilters,
              onPressed: () => _openFilterSheet(context, catalog),
            ),
          ],
        );
      },
    );
  }
}
