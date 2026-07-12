import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../../config/map_config.dart';

class MapTileLayer extends StatelessWidget {
  const MapTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TileLayer(
      urlTemplate: MapConfig.tileUrlForBrightness(
        isDark ? Brightness.dark : Brightness.light,
      ),
      subdomains: MapConfig.tileSubdomains,
      userAgentPackageName: MapConfig.userAgentPackageName,
      tileProvider: CancellableNetworkTileProvider(),
      errorTileCallback: (tile, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('MapTileLayer error: $error');
        }
      },
    );
  }
}
