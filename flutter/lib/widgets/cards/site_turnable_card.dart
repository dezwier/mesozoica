import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_world_map.dart';
import 'site_card_back.dart';
import 'site_card_front.dart';
import 'site_status_helper.dart';
import 'turnable_y_axis_card.dart';

class SiteTurnableCard extends StatefulWidget {
  const SiteTurnableCard({
    super.key,
    required this.site,
    this.turnable = true,
    this.enableDragFlip = true,
    this.autoFlipOnce = false,
    this.autoFlipHoldOnBack = Duration.zero,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.38,
    this.outerPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.fixedFaceHeight,
    this.mapTileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
    this.onSiteUpdated,
  });

  final SiteSummary site;
  final bool turnable;
  final bool enableDragFlip;
  final bool autoFlipOnce;
  final Duration autoFlipHoldOnBack;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final EdgeInsets outerPadding;
  final double? fixedFaceHeight;
  final Widget Function() mapTileLayerBuilder;
  final ValueChanged<SiteSummary>? onSiteUpdated;

  @override
  State<SiteTurnableCard> createState() => _SiteTurnableCardState();
}

class _SiteTurnableCardState extends State<SiteTurnableCard> {
  late SiteSummary _site;

  @override
  void initState() {
    super.initState();
    _site = widget.site;
  }

  @override
  void didUpdateWidget(covariant SiteTurnableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.siteId != widget.site.siteId ||
        oldWidget.site.status != widget.site.status ||
        oldWidget.site.viewerHasSurveyed != widget.site.viewerHasSurveyed) {
      _site = widget.site;
    }
  }

  Future<void> _onStatusSelected(String status) async {
    final updated = await applySiteStatusSelection(
      context,
      _site,
      newStatus: status,
    );
    if (updated == null || !mounted) return;
    setState(() => _site = updated);
    widget.onSiteUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final hasStatus = (_site.status?.trim().isNotEmpty ?? false);
    final isAdmin =
        context.watch<AuthController>().currentUser?.isAdmin ?? false;

    return TurnableYAxisCard(
      resetIdentity: _site.siteId,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: widget.outerPadding,
      fixedFaceHeight: widget.fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      enableDragFlip: widget.enableDragFlip,
      autoFlipOnce: widget.autoFlipOnce,
      autoFlipHoldOnBack: widget.autoFlipHoldOnBack,
      front: SiteCardFront(
        site: _site,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
        onStatusSelected: hasStatus && isAdmin ? _onStatusSelected : null,
      ),
      back: SiteCardBack(
        site: _site,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        mapTileLayerBuilder: widget.mapTileLayerBuilder,
      ),
    );
  }
}
