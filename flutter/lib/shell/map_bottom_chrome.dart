import 'package:flutter/material.dart';

import '../theme/map_chrome_decorations.dart';
import '../theme/map_chrome_theme.dart';
import 'map_chrome_insets.dart';

/// Vintage leather bottom entry points: Sites, Fossils, Dinosaurs, Tools.
class MapBottomChrome extends StatelessWidget {
  const MapBottomChrome({
    super.key,
    required this.onOpenSites,
    required this.onOpenFossils,
    required this.onOpenDinosaurs,
    required this.onOpenTools,
  });

  final VoidCallback onOpenSites;
  final VoidCallback onOpenFossils;
  final VoidCallback onOpenDinosaurs;
  final VoidCallback onOpenTools;

  static const _sitesAsset = 'assets/images/chrome/nav/sites.png';
  static const _fossilsAsset = 'assets/images/chrome/nav/fossils.png';
  static const _dinosaursAsset = 'assets/images/chrome/nav/dinosaurs.png';
  static const _toolsAsset = 'assets/images/chrome/nav/tools.png';

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              // Align with tool HUD side inset; sit closer to bottom.
              padding: const EdgeInsets.fromLTRB(
                MapChromeInsets.bottomBarSidePad,
                0,
                MapChromeInsets.bottomBarSidePad,
                2,
              ),
              child: SizedBox(
                height: MapChromeInsets.bottomRowHeight - 2,
                child: DecoratedBox(
                  decoration: MapChromeDecorations.leatherPanel(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _NavItem(
                            label: 'SITES',
                            asset: _sitesAsset,
                            onTap: onOpenSites,
                          ),
                        ),
                        const _NavSeparator(),
                        Expanded(
                          child: _NavItem(
                            label: 'FOSSILS',
                            asset: _fossilsAsset,
                            onTap: onOpenFossils,
                          ),
                        ),
                        const _NavSeparator(),
                        Expanded(
                          child: _NavItem(
                            label: 'DINOSAURS',
                            asset: _dinosaursAsset,
                            onTap: onOpenDinosaurs,
                          ),
                        ),
                        const _NavSeparator(),
                        Expanded(
                          child: _NavItem(
                            label: 'TOOLS',
                            asset: _toolsAsset,
                            onTap: onOpenTools,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft brass vertical strip between nav tabs.
class _NavSeparator extends StatelessWidget {
  const _NavSeparator();

  @override
  Widget build(BuildContext context) {
    // Explicit height — a width-only SizedBox in a Row collapses to 0 tall.
    return const SizedBox(
      width: 12,
      child: Center(
        child: SizedBox(
          width: 2.5,
          height: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(1.25)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00C2B29A), // fade out
                  Color(0x99C2B29A), // brassLight @ ~0.6
                  Color(0x8A9A8A74), // brassMid @ ~0.54
                  Color(0x99C2B29A),
                  Color(0x00C2B29A), // fade out
                ],
                stops: [0.0, 0.22, 0.5, 0.78, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        borderRadius: BorderRadius.circular(12),
        splashColor: MapChromeTheme.parchment.withValues(alpha: 0.25),
        highlightColor: MapChromeTheme.parchment.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: _pressed
                ? MapChromeDecorations.parchmentPanel(
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: MapChromeInsets.bottomIconSize,
                  height: MapChromeInsets.bottomIconSize,
                  child: Image.asset(
                    widget.asset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _pressed
                        ? MapChromeTheme.brownText
                        : MapChromeTheme.mutedGold,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: MapChromeTheme.serifFont,
                    letterSpacing: 0.4,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
