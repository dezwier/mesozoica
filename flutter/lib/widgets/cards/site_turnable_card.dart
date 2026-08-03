import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../theme/dino_card_theme.dart';
import 'card_discard_helper.dart';
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
    this.enableLongPressActions = false,
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
  final bool enableLongPressActions;
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
  SiteSummary? _exactOddsPeek;
  bool _exactOddsLoading = false;
  int? _exactOddsRequestedForId;
  bool _exactOddsQueued = false;
  final SiteService _siteService = SiteService();

  bool get _hasExactOdds =>
      _site.oddDinoCount != null ||
      _site.oddFossilCount != null ||
      _site.oddCompleteness != null ||
      _site.oddQuality != null ||
      _site.oddDepth != null;

  SiteSummary get _displaySite {
    final peek = _exactOddsPeek;
    if (peek != null && peek.siteId == _site.siteId) return peek;
    return _site;
  }

  @override
  void initState() {
    super.initState();
    _site = widget.site;
  }

  @override
  void dispose() {
    _siteService.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SiteTurnableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.siteId != widget.site.siteId ||
        oldWidget.site.status != widget.site.status ||
        oldWidget.site.viewerHasDocumented != widget.site.viewerHasDocumented ||
        oldWidget.site.exploredDistanceM != widget.site.exploredDistanceM ||
        oldWidget.site.oddDinoBand?.effectiveAccuracy !=
            widget.site.oddDinoBand?.effectiveAccuracy) {
      _site = widget.site;
      _exactOddsPeek = null;
      _exactOddsRequestedForId = null;
      _exactOddsLoading = false;
    } else if (_hasExactOdds) {
      _site = widget.site;
    }
  }

  void _queueExactOddsPeek({required bool showAdminUi}) {
    if (_exactOddsQueued) return;
    _exactOddsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _exactOddsQueued = false;
      if (!mounted) return;
      unawaited(_syncExactOddsPeek(showAdminUi: showAdminUi));
    });
  }

  Future<void> _syncExactOddsPeek({required bool showAdminUi}) async {
    if (!showAdminUi) {
      if (_exactOddsPeek != null) {
        setState(() => _exactOddsPeek = null);
      }
      _exactOddsRequestedForId = null;
      _exactOddsLoading = false;
      return;
    }
    if (_hasExactOdds) return;
    if (_exactOddsLoading && _exactOddsRequestedForId == _site.siteId) return;
    if (_exactOddsPeek?.siteId == _site.siteId) return;

    final siteId = _site.siteId;
    final dataSource = _site.isFieldOccurrence
        ? CatalogDataSource.field
        : CatalogDataSource.archive;
    _exactOddsRequestedForId = siteId;
    _exactOddsLoading = true;
    try {
      final peeked = await _siteService.fetchSiteById(
        siteId,
        dataSource: dataSource,
        includeExactOdds: true,
      );
      if (!mounted || _site.siteId != siteId) return;
      setState(() => _exactOddsPeek = peeked);
    } catch (_) {
      // Keep blurry bands only; exact marker stays hidden.
    } finally {
      if (mounted && _exactOddsRequestedForId == siteId) {
        _exactOddsLoading = false;
      }
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
    final displaySite = _displaySite;
    final hasStatus = (displaySite.status?.trim().isNotEmpty ?? false);
    final showAdminUi = context.watch<AuthController>().showAdminUi;
    _queueExactOddsPeek(showAdminUi: showAdminUi);

    return TurnableYAxisCard(
      resetIdentity: displaySite.siteId,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: widget.outerPadding,
      fixedFaceHeight: widget.fixedFaceHeight,
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: widget.turnable,
      enableDragFlip: widget.enableDragFlip,
      enableLongPressActions: widget.enableLongPressActions,
      onSettingsPressed: widget.enableLongPressActions
          ? () => openInventoryCardSettings(
                context: context,
                onThrowAway: () =>
                    discardSiteFromInventory(context, displaySite),
              )
          : null,
      autoFlipOnce: widget.autoFlipOnce,
      autoFlipHoldOnBack: widget.autoFlipHoldOnBack,
      front: SiteCardFront(
        site: displaySite,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        overlayHeightFactor: widget.overlayHeightFactor,
        onStatusSelected: hasStatus && showAdminUi ? _onStatusSelected : null,
      ),
      back: SiteCardBack(
        site: displaySite,
        titleFontSize: widget.titleFontSize,
        subtitleFontSize: widget.subtitleFontSize,
        mapTileLayerBuilder: widget.mapTileLayerBuilder,
      ),
    );
  }
}
