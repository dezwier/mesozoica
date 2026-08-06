import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../controllers/notification_controller.dart';

List<SingleChildWidget> buildNotificationProviders() => [
  ChangeNotifierProvider(create: (_) => NotificationController()),
];
