import 'package:flutter/material.dart';

import '../../widgets/common/empty_screen_placeholder.dart';

class TreeScreen extends StatelessWidget {
  const TreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyScreenPlaceholder(
      icon: Icons.account_tree_outlined,
      title: 'Tree of Life',
      subtitle: 'Phylogeny explorer coming soon.',
    );
  }
}
