import 'package:flutter/material.dart';

import '../dino/dino_screen.dart';
import '../fossil/fossil_screen.dart';
import '../site/site_screen.dart';
import '../tool/tool_screen.dart';

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
  static const _toolTabIndex = 3;

  late final TabController _tabController;
  late final AnimationController _tabBarVisibilityController;
  final _siteKey = GlobalKey<SiteScreenState>();
  final _fossilKey = GlobalKey<FossilScreenState>();
  final _dinoKey = GlobalKey<DinoScreenState>();
  final _toolKey = GlobalKey<ToolScreenState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: _dinoTabIndex,
    );
    _tabBarVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _syncTabBarWithActiveTab();
    setState(() {});
  }

  void _onTabScrollUpdate(double offset, double delta) {
    if (offset <= 0) {
      _showTabBar();
      return;
    }
    if (delta > 1) {
      _hideTabBar();
    } else if (delta < -1) {
      _showTabBar();
    }
  }

  void _syncTabBarWithActiveTab() {
    final offset = switch (_tabController.index) {
      _siteTabIndex => _siteKey.currentState?.scrollOffset ?? 0,
      _fossilTabIndex => _fossilKey.currentState?.scrollOffset ?? 0,
      _toolTabIndex => _toolKey.currentState?.scrollOffset ?? 0,
      _ => _dinoKey.currentState?.scrollOffset ?? 0,
    };
    if (offset <= 0) {
      _showTabBar();
    } else {
      _hideTabBar();
    }
  }

  void _hideTabBar() {
    if (_tabBarVisibilityController.status == AnimationStatus.reverse ||
        _tabBarVisibilityController.value == 0) {
      return;
    }
    _tabBarVisibilityController.reverse();
  }

  void _showTabBar() {
    if (_tabBarVisibilityController.status == AnimationStatus.forward ||
        _tabBarVisibilityController.value == 1) {
      return;
    }
    _tabBarVisibilityController.forward();
  }

  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _syncTabBarWithActiveTab();
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _tabBarVisibilityController.dispose();
    super.dispose();
  }

  void scrollActiveTabToTop() {
    _showTabBar();
    switch (_tabController.index) {
      case _siteTabIndex:
        _siteKey.currentState?.scrollToTop();
      case _fossilTabIndex:
        _fossilKey.currentState?.scrollToTop();
      case _dinoTabIndex:
        _dinoKey.currentState?.scrollToTop();
      case _toolTabIndex:
        _toolKey.currentState?.scrollToTop();
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
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _tabBarVisibilityController,
            curve: Curves.easeInOut,
            reverseCurve: Curves.easeInOut,
          ),
          axisAlignment: -1,
          child: TabBar(
            controller: _tabController,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
            indicatorColor: colorScheme.primary,
            tabs: const [
              Tab(text: 'Site'),
              Tab(text: 'Fossil'),
              Tab(text: 'Dinosaur'),
              Tab(text: 'Tool'),
            ],
          ),
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
                  onScrollUpdate: _onTabScrollUpdate,
                ),
              ),
              _CatalogTab(
                child: FossilScreen(
                  key: _fossilKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _fossilTabIndex,
                  onScrollUpdate: _onTabScrollUpdate,
                ),
              ),
              _CatalogTab(
                child: DinoScreen(
                  key: _dinoKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _dinoTabIndex,
                  onScrollUpdate: _onTabScrollUpdate,
                ),
              ),
              _CatalogTab(
                child: ToolScreen(
                  key: _toolKey,
                  isActive:
                      showActiveTabContent && activeTabIndex == _toolTabIndex,
                  onScrollUpdate: _onTabScrollUpdate,
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
