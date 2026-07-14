import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/common/gradient_app_bar.dart';
import '../controllers/theme_controller.dart';
import '../screens/catalog/catalog_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/tree/tree_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _mapTabIndex = 0;
  static const _catalogTabIndex = 1;
  static const _treeTabIndex = 2;

  int _index = _catalogTabIndex;
  final _catalogScreenKey = GlobalKey<CatalogScreenState>();

  void _onDestinationSelected(int index) {
    if (index == _index && index == _catalogTabIndex) {
      _catalogScreenKey.currentState?.scrollActiveTabToTop();
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return Scaffold(
      appBar: GradientAppBar(
        title: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Image.asset('assets/images/logo.png', height: 32),
        ),
        actions: [
          IconButton(
            tooltip: themeController.isDark ? 'Light mode' : 'Dark mode',
            onPressed: themeController.toggle,
            icon: Icon(
              themeController.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          MapScreen(isActive: _index == _mapTabIndex),
          CatalogScreen(
            key: _catalogScreenKey,
            isActive: _index == _catalogTabIndex,
          ),
          TreeScreen(isActive: _index == _treeTabIndex),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.45),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark),
              label: 'Catalog',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_tree_outlined),
              selectedIcon: Icon(Icons.account_tree),
              label: 'Tree',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outlined),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

}
