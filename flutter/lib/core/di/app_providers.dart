import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/splash_hold_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../features/collection/providers.dart';
import '../../features/discovery/providers.dart';
import '../../features/expeditions/providers.dart';
import '../../features/notifications/providers.dart';
import '../../features/phylogeny/providers.dart';
import '../../features/profile/providers.dart';
import '../../features/progression/providers.dart';
import '../../services/location_service.dart';

/// Application composition root.
///
/// Provider ownership is kept out of widgets so each feature can migrate to a
/// feature-local composition function without changing the app shell.
List<SingleChildWidget> buildAppProviders({
  required ThemeController themeController,
  required CatalogModeController catalogModeController,
}) {
  return [
    ChangeNotifierProvider.value(value: themeController),
    ChangeNotifierProvider.value(value: catalogModeController),
    ChangeNotifierProvider(create: (_) => SplashHoldController()),
    ChangeNotifierProvider(create: (_) => LocationService()..loadPreferences()),
    ...buildProfileProviders(),
    ...buildNotificationProviders(),
    ...buildCollectionProviders(),
    ...buildExpeditionProviders(),
    ...buildPhylogenyProviders(),
    ...buildDiscoveryProviders(),
    ...buildProgressionProviders(),
  ];
}
