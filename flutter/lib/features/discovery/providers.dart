import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/field_session_coordinator.dart';
import '../../controllers/map_controller.dart';
import '../../controllers/site_exploration_controller.dart';
import '../../controllers/weather_controller.dart';
import '../../services/location_service.dart';

List<SingleChildWidget> buildDiscoveryProviders() => [
  ChangeNotifierProvider(
    create: (context) =>
        WeatherController(locationService: context.read<LocationService>()),
  ),
  ChangeNotifierProvider(
    create: (context) => MapController(
      catalogModeController: context.read<CatalogModeController>(),
    ),
  ),
  ChangeNotifierProvider(create: (_) => FieldSessionCoordinator()),
  ChangeNotifierProvider(create: (_) => FieldDiscoveryCoordinator()),
  ChangeNotifierProvider(create: (_) => SiteExplorationController()),
];
