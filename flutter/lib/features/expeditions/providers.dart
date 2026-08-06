import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/aerial_session_controller.dart';
import '../../controllers/disguise_session_controller.dart';
import '../../controllers/formation_map_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/main_param_buff_controller.dart';
import '../../controllers/orbit_survey_controller.dart';
import '../../controllers/terrain_echo_controller.dart';

List<SingleChildWidget> buildExpeditionProviders() => [
  ChangeNotifierProvider(create: (_) => AerialSessionController()),
  ChangeNotifierProvider(create: (_) => GuidanceSessionController()),
  ChangeNotifierProvider(create: (_) => OrbitSurveyController()),
  ChangeNotifierProvider(create: (_) => FormationMapController()),
  ChangeNotifierProvider(create: (_) => TerrainEchoController()),
  ChangeNotifierProvider(create: (_) => MainParamBuffController()),
  ChangeNotifierProvider(create: (_) => DisguiseSessionController()),
];
