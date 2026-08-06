import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/xp_award_controller.dart';

List<SingleChildWidget> buildProgressionProviders() => [
  ChangeNotifierProvider(create: (_) => XpAwardController()),
];
