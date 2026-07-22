import 'package:flutter/material.dart';

import '../dino/dino_screen.dart';
import '../fossil/fossil_screen.dart';
import '../site/site_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    this.isActive = false,
  });

  final bool isActive;

  @override
  State<CatalogScreen> createState() => CatalogScreenState();
}

class CatalogScreenState extends State<CatalogScreen>
    with TickerProviderStateMixin {
  static const _siteTabIndex = 0;
  static const _fossilTabIndex = 1;
  static const _dinoTabIndex = 2;

  late final TabController _tabController;
  final _siteKey = GlobalKey<SiteScreenState>();
  final _fossilKey = GlobalKey<FossilScreenState>();
  final _dinoKey = GlobalKey<DinoScreenState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _dinoTabIndex,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void scrollActiveTabToTop() {
    switch (_tabController.index) {
      case _siteTabIndex:
        _siteKey.currentState?.scrollToTop();
      case _fossilTabIndex:
        _fossilKey.currentState?.scrollToTop();
      case _dinoTabIndex:
        _dinoKey.currentState?.scrollToTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeTabIndex = _tabController.index;
    final showActiveTabContent =
        widget.isActive && !_tabController.indexIsChanging;

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
          indicatorColor: colorScheme.primary,
          tabs: const [
            Tab(text: 'Site'),
            Tab(text: 'Fossil'),
            Tab(text: 'Dinosaur'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _CatalogTab(
                child: SiteScreen(
                  key: _siteKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _siteTabIndex,
                ),
              ),
              _CatalogTab(
                child: FossilScreen(
                  key: _fossilKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _fossilTabIndex,
                ),
              ),
              _CatalogTab(
                child: DinoScreen(
                  key: _dinoKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _dinoTabIndex,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CatalogTab extends StatefulWidget {
  const _CatalogTab({required this.child});

  final Widget child;

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
