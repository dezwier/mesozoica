import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/discovery_config.dart';
import '../../controllers/xp_award_controller.dart';
import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../utils/xp_source_labels.dart';
import 'card_detail_sheet.dart';
import 'celebration_title_badge.dart';
import 'site_turnable_card.dart';

/// Celebration overlay after proximity (or notification-tap) discovery /
/// documentation / identification.
///
/// Big-event XP for this celebration is claimed from [XpAwardController] and
/// embedded in the title plaque (not shown as a floating badge).
Future<void> showSiteDiscoveryCelebration(
  BuildContext context, {
  SiteSummary? site,
  int? siteId,
  SiteService? siteService,
  String title = CelebrationTitles.siteDiscovered,
  List<XpAward>? xpAwards,
}) {
  assert(site != null || siteId != null);
  final awards = xpAwards ??
      _claimCelebrationXp(
        context,
        kSiteDiscoveryCelebrationXpKeys,
      );
  return CardDetailSheet.show<void>(
    context,
    clearTopForXpBadges: false,
    builder: (context) => _SiteDiscoveryCelebrationSheet(
      site: site,
      siteId: siteId,
      siteService: siteService,
      title: title,
      xpAwards: awards,
    ),
  );
}

/// Same card celebration used when a site becomes fully documented.
Future<void> showSiteDocumentationCelebration(
  BuildContext context, {
  SiteSummary? site,
  int? siteId,
  SiteService? siteService,
  List<XpAward>? xpAwards,
}) {
  final awards = xpAwards ??
      _claimCelebrationXp(
        context,
        kSiteDocumentationCelebrationXpKeys,
      );
  return showSiteDiscoveryCelebration(
    context,
    site: site,
    siteId: siteId,
    siteService: siteService,
    title: CelebrationTitles.siteDocumented,
    xpAwards: awards,
  );
}

/// Same card celebration used when the identification quiz is completed.
Future<void> showSiteIdentifiedCelebration(
  BuildContext context, {
  SiteSummary? site,
  int? siteId,
  SiteService? siteService,
  List<XpAward>? xpAwards,
}) {
  final awards = xpAwards ??
      _claimCelebrationXp(
        context,
        kSiteIdentificationCelebrationXpKeys,
        mergeSameKey: true,
      );
  return showSiteDiscoveryCelebration(
    context,
    site: site,
    siteId: siteId,
    siteService: siteService,
    title: CelebrationTitles.siteIdentified,
    xpAwards: awards,
  );
}

List<XpAward> _claimCelebrationXp(
  BuildContext context,
  Set<String> keys, {
  bool mergeSameKey = false,
}) {
  try {
    return context.read<XpAwardController>().claimCelebrationAwards(
          keys,
          mergeSameKey: mergeSameKey,
        );
  } on ProviderNotFoundException {
    return const [];
  }
}

class _SiteDiscoveryCelebrationSheet extends StatefulWidget {
  const _SiteDiscoveryCelebrationSheet({
    this.site,
    this.siteId,
    this.siteService,
    required this.title,
    this.xpAwards = const [],
  });

  final SiteSummary? site;
  final int? siteId;
  final SiteService? siteService;
  final String title;
  final List<XpAward> xpAwards;

  @override
  State<_SiteDiscoveryCelebrationSheet> createState() =>
      _SiteDiscoveryCelebrationSheetState();
}

class _SiteDiscoveryCelebrationSheetState
    extends State<_SiteDiscoveryCelebrationSheet>
    with SingleTickerProviderStateMixin {
  late final SiteService _service;
  late final bool _ownsService;
  late final Future<SiteSummary> _siteFuture;
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    final existing = widget.site;
    if (existing != null) {
      _siteFuture = Future.value(existing);
    } else {
      _siteFuture = _service.fetchSiteById(
        widget.siteId!,
        dataSource: CatalogDataSource.field,
      );
    }
    _scaleController = AnimationController(
      vsync: this,
      duration: DiscoveryConfig.celebrationScaleIn,
    );
    _scale = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SiteSummary>(
      future: _siteFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error?.toString() ?? 'Could not load site.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          );
        }

        return ScaleTransition(
          scale: _scale,
          child: CardDetailSheetContent(
            clearTopForXpBadges: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CelebrationTitleBadge(
                  title: widget.title,
                  xpAwards: widget.xpAwards,
                ),
                const SizedBox(height: 14),
                SiteTurnableCard(
                  site: snapshot.data!,
                  autoFlipOnce: true,
                  autoFlipHoldOnBack: DiscoveryConfig.autoFlipHoldOnBack,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
