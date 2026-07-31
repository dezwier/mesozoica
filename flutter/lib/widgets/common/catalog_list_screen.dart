import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_controller.dart';
import '../../shell/overlay_bottom_chrome.dart';
import '../../shell/shell_overlay_panel.dart';
import '../../theme/dino_card_theme.dart';
import 'cover_flow_carousel.dart';
import 'overlay_chrome_button.dart';

/// Generic vertical Cover Flow / paginate / refresh host shared by the dino,
/// fossil, site, and tool catalog screens. Each screen supplies its card
/// [itemBuilder], empty-state copy, and floating actions; this widget owns
/// load-more paging and loading/error/empty states.
class CatalogListScreen<C extends CatalogController<T>, T>
    extends StatefulWidget {
  const CatalogListScreen({
    super.key,
    this.isActive = true,
    required this.itemBuilder,
    required this.emptyMessageBuilder,
    this.isInitialLoading,
    this.floatingActionsBuilder,
  });

  final bool isActive;

  /// [isFocused] is true for the focused Cover Flow card only.
  final Widget Function(
    BuildContext context,
    T item, {
    required bool isFocused,
    required double? fixedFaceHeight,
  }) itemBuilder;
  final String Function(BuildContext context, C catalog) emptyMessageBuilder;

  /// Full-screen spinner condition. Defaults to
  /// `catalog.loading && catalog.items.isEmpty`.
  final bool Function(C catalog)? isInitialLoading;

  /// Leading bottom-chrome actions (Close is appended on the right).
  final List<Widget> Function(BuildContext context, C catalog)?
      floatingActionsBuilder;

  @override
  State<CatalogListScreen<C, T>> createState() =>
      CatalogListScreenState<C, T>();
}

class CatalogListScreenState<C extends CatalogController<T>, T>
    extends State<CatalogListScreen<C, T>> {
  final GlobalKey<CoverFlowCarouselState> _coverFlowKey =
      GlobalKey<CoverFlowCarouselState>();
  Timer? _pageDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<C>().refresh();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    if (mounted) {
      context.read<C>().refresh();
    }
  }

  @override
  void dispose() {
    _pageDebounceTimer?.cancel();
    super.dispose();
  }

  void scrollToTop() {
    _coverFlowKey.currentState?.animateToFirst();
  }

  void _onPageChanged(int page, C catalog) {
    _pageDebounceTimer?.cancel();
    _pageDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final count = catalog.items.length;
      if (count == 0) return;
      if (page >= count * 0.8) {
        context.read<C>().loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<C>(
      builder: (context, catalog, _) {
        return Stack(
          children: [
            Positioned.fill(child: _buildBody(context, catalog)),
            if (widget.isActive)
              OverlayBottomChrome(
                child: _buildBottomChrome(context, catalog),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomChrome(BuildContext context, C catalog) {
    final scope = ShellOverlayScope.maybeOf(context);
    final actions =
        widget.floatingActionsBuilder?.call(context, catalog) ?? const [];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions) ...[
          action,
          const SizedBox(width: 8),
        ],
        if (scope != null)
          OverlayChromeButton(
            onPressed: scope.onClose,
            icon: Icons.close_rounded,
            label: 'Close',
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, C catalog) {
    // Reserve the bottom chrome band so the focused card centers in the
    // space between the top of the screen and the dismiss row.
    return Padding(
      padding: EdgeInsets.only(
        bottom: ShellOverlayPanel.bottomChromeHeight(context),
      ),
      child: _buildBodyContent(context, catalog),
    );
  }

  Widget _buildBodyContent(BuildContext context, C catalog) {
    final isInitialLoading = widget.isInitialLoading?.call(catalog) ??
        (catalog.loading && catalog.items.isEmpty);
    // Light copy for readability on the dimmed map scrim.
    final overlayTextStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFFF5F5F5),
        );

    if (isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (catalog.error != null && catalog.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                catalog.error!,
                textAlign: TextAlign.center,
                style: overlayTextStyle,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => catalog.refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (catalog.isEmpty) {
      return Center(
        child: Text(
          widget.emptyMessageBuilder(context, catalog),
          textAlign: TextAlign.center,
          style: overlayTextStyle,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size to image aspect (3:4 / 1086×1448). Prefer full width; if the
        // available height band is shorter, shrink width to match so the
        // chrome never letterboxes beside the art.
        const horizontalInset = 16.0 * 2;
        const verticalInset = 8.0 * 2;
        final maxFaceWidth =
            (constraints.maxWidth - horizontalInset).clamp(120.0, 2000.0);
        final maxFaceHeight = (constraints.maxHeight * 0.72 - verticalInset)
            .clamp(120.0, 2000.0);
        final heightFromWidth =
            maxFaceWidth / DinoCardTheme.cardAspectRatio;
        final double faceHeight;
        if (heightFromWidth <= maxFaceHeight) {
          faceHeight = heightFromWidth;
        } else {
          faceHeight = maxFaceHeight;
        }
        final slotHeight = faceHeight + verticalInset;
        final viewportFraction =
            (slotHeight / constraints.maxHeight).clamp(0.55, 0.85);

        return CoverFlowCarousel(
          key: _coverFlowKey,
          itemCount: catalog.items.length +
              (catalog.isLoadingMore ? 1 : 0),
          viewportFraction: viewportFraction,
          onPageChanged: (page) => _onPageChanged(page, catalog),
          onPullDismiss: ShellOverlayScope.maybeOf(context)?.onClose,
          itemBuilder: (context, index, isFocused) {
            if (index >= catalog.items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return widget.itemBuilder(
              context,
              catalog.items[index],
              isFocused: isFocused,
              fixedFaceHeight: faceHeight,
            );
          },
        );
      },
    );
  }
}
