import 'package:mesozoica/config/map_config.dart';

Future<void> configureMapboxAccessToken() async {
  // Mapbox Maps SDK v2 has no web renderer; the field map uses flutter_map.
  if (MapConfig.hasMapboxAccessToken) {
    return;
  }
}
