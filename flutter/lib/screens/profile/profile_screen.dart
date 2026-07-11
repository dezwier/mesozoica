import 'package:flutter/material.dart';

import '../../widgets/common/empty_screen_placeholder.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyScreenPlaceholder(
      icon: Icons.person_outlined,
      title: 'Profile',
      subtitle: 'Account and settings coming soon.',
    );
  }
}
