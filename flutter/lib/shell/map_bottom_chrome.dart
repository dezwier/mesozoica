import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/tool_catalog_controller.dart';
import '../services/auth_service.dart';
import '../theme/dino_card_theme.dart';
import '../widgets/cards/tool_card_image.dart';
import 'map_chrome_insets.dart';

/// Floating bottom entry points: profile, catalog, and tools on the lower left.
class MapBottomChrome extends StatefulWidget {
  const MapBottomChrome({
    super.key,
    required this.onOpenProfile,
    required this.onOpenCatalog,
    required this.onOpenTools,
  });

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenTools;

  static const double _buttonSize = 60;
  static const double _buttonGap = 16;

  @override
  State<MapBottomChrome> createState() => _MapBottomChromeState();
}

class _MapBottomChromeState extends State<MapBottomChrome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ToolCatalogController>().ensureChromeImage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Stack(
        children: [
          // Full-width fade is visual only; otherwise it blocks the map filter FAB.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: MapChromeInsets.bottomRowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ProfileEntry(
                        size: MapBottomChrome._buttonSize,
                        onTap: widget.onOpenProfile,
                      ),
                      const SizedBox(width: MapBottomChrome._buttonGap),
                      _LabeledChromeButton(
                        size: MapBottomChrome._buttonSize,
                        label: 'Catalog',
                        onTap: widget.onOpenCatalog,
                        child: Image.asset(
                          'assets/images/cards/dinosaur_card_front_placeholder.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: MapBottomChrome._buttonGap),
                      _ToolsEntry(
                        size: MapBottomChrome._buttonSize,
                        onTap: widget.onOpenTools,
                      ),
                    ],
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

class _ToolsEntry extends StatelessWidget {
  const _ToolsEntry({
    required this.size,
    required this.onTap,
  });

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer<ToolCatalogController>(
      builder: (context, catalog, _) {
        final imageUrl = catalog.chromeImageUrl;
        final curated = ToolCardImage.isCuratedCardImageUrl(imageUrl);
        return _LabeledChromeButton(
          size: size,
          label: 'Tools',
          onTap: onTap,
          child: curated
              ? CachedNetworkImage(
                  imageUrl: imageUrl!.trim(),
                  fit: BoxFit.cover,
                  errorWidget: (context, _, _) => _fallbackToolImage(),
                )
              : _fallbackToolImage(),
        );
      },
    );
  }

  Widget _fallbackToolImage() {
    return Image.asset(
      DinoCardTheme.sitePlaceholderAsset,
      fit: BoxFit.cover,
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({
    required this.size,
    required this.onTap,
  });

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final profile = auth.currentUser;
        final imageUrl =
            profile != null ? AuthService.imageUrl(profile.profileImage) : '';
        final label = _profileLabel(profile?.username, profile?.displayName);

        return _LabeledChromeButton(
          size: size,
          label: label,
          onTap: onTap,
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, _, _) => _fallbackAvatar(),
                )
              : _fallbackAvatar(),
        );
      },
    );
  }

  static String _profileLabel(String? username, String? displayName) {
    final name = (username != null && username.trim().isNotEmpty)
        ? username.trim()
        : (displayName ?? '').trim();
    if (name.isEmpty) return 'Profile';
    return _toTitleCase(name);
  }

  static String _toTitleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  Widget _fallbackAvatar() {
    return Image.asset(
      'assets/images/logo.png',
      fit: BoxFit.cover,
    );
  }
}

class _LabeledChromeButton extends StatelessWidget {
  const _LabeledChromeButton({
    required this.size,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final double size;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapChromeCircleButton(
            size: size,
            onTap: onTap,
            child: child,
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size + 28),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.1,
                shadows: [
                  Shadow(
                    color: Color(0xCC000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapChromeCircleButton extends StatelessWidget {
  const _MapChromeCircleButton({
    required this.size,
    required this.onTap,
    required this.child,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white, width: 2.5),
      ),
      color: scheme.surface.withValues(alpha: 0.95),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: child,
        ),
      ),
    );
  }
}
