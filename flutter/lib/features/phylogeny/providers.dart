import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/dinosaur_catalog_controller.dart';
import '../../controllers/phylo_tree_controller.dart';

List<SingleChildWidget> buildPhylogenyProviders() => [
  ChangeNotifierProvider(
    create: (context) => PhyloTreeController(
      catalogController: context.read<DinosaurCatalogController>(),
    ),
  ),
];
