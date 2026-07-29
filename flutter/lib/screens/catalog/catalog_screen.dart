import 'package:flutter/material.dart';

import '../../widgets/common/chrome_action_button.dart';
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

class CatalogScreenState extends State<CatalogScreen> {
  static const _siteTabIndex = 0;
  static const _fossilTabIndex = 1;
  static const _dinoTabIndex = 2;

  static const _categoryButtonHeight = 44.0;
  static const _categoryGap = 6.0;

  int _index = _dinoTabIndex;
  final _siteKey = GlobalKey<SiteScreenState>();
  final _fossilKey = GlobalKey<FossilScreenState>();
  final _dinoKey = GlobalKey<DinoScreenState>();

  void scrollActiveTabToTop() {
    switch (_index) {
      case _siteTabIndex:
        _siteKey.currentState?.scrollToTop();
      case _fossilTabIndex:
        _fossilKey.currentState?.scrollToTop();
      case _dinoTabIndex:
        _dinoKey.currentState?.scrollToTop();
    }
  }

  void _selectCategory(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final showActiveTabContent = widget.isActive;

    // Stack category buttons over the carousel so Cover Flow gets the same
    // viewport height as Tools (buttons no longer shrink the card area).
    return Stack(
      fit: StackFit.expand,
      children: [
        IndexedStack(
          index: _index,
          children: [
            SiteScreen(
              key: _siteKey,
              isActive: showActiveTabContent && _index == _siteTabIndex,
            ),
            FossilScreen(
              key: _fossilKey,
              isActive: showActiveTabContent && _index == _fossilTabIndex,
            ),
            DinoScreen(
              key: _dinoKey,
              isActive: showActiveTabContent && _index == _dinoTabIndex,
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: _categoryButtonHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ChromeActionButton(
                      label: 'Site',
                      selected: _index == _siteTabIndex,
                      onPressed: () => _selectCategory(_siteTabIndex),
                    ),
                  ),
                  const SizedBox(width: _categoryGap),
                  Expanded(
                    child: ChromeActionButton(
                      label: 'Fossil',
                      selected: _index == _fossilTabIndex,
                      onPressed: () => _selectCategory(_fossilTabIndex),
                    ),
                  ),
                  const SizedBox(width: _categoryGap),
                  Expanded(
                    child: ChromeActionButton(
                      label: 'Dinosaur',
                      selected: _index == _dinoTabIndex,
                      onPressed: () => _selectCategory(_dinoTabIndex),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
