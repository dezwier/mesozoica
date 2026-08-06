import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/walk_distance_controller.dart';

List<SingleChildWidget> buildProfileProviders() => [
  ChangeNotifierProvider(create: (_) => AuthController()..initialize()),
  ChangeNotifierProvider(create: (_) => WalkDistanceController()),
];
