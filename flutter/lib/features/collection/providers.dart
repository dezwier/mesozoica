import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/dinosaur_catalog_controller.dart';
import '../../controllers/fossil_catalog_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../services/location_service.dart';

List<SingleChildWidget> buildCollectionProviders() => [
  ChangeNotifierProvider(create: (_) => DinosaurCatalogController()),
  ChangeNotifierProvider(
    create: (context) => FossilCatalogController(
      catalogModeController: context.read<CatalogModeController>(),
    ),
  ),
  ChangeNotifierProvider(
    create: (context) => SiteCatalogController(
      catalogModeController: context.read<CatalogModeController>(),
      locationService: context.read<LocationService>(),
    ),
  ),
  ChangeNotifierProvider(create: (_) => ToolCatalogController()),
];
