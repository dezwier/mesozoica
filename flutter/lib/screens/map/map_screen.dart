import 'package:flutter/material.dart';

import '../../widgets/common/empty_screen_placeholder.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyScreenPlaceholder(
      icon: Icons.map_outlined,
      title: 'Map',
      subtitle: 'Discovery map coming soon.',
    );
  }
}
