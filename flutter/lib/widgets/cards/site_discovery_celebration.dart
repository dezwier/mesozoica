import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/discovery_config.dart';
import '../../controllers/xp_award_controller.dart';
import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import '../../utils/xp_source_labels.dart';
import '../../features/notifications/domain/celebration_event.dart';
import 'card_detail_sheet.dart';
import 'celebration_title_badge.dart';
import 'site_turnable_card.dart';

List<XpAward> _claimCelebrationXp(
  BuildContext context,
  Set<String> keys, {
  bool mergeSameKey = false,
  bool oneEvent = true,
}) {
  try {
    return context.read<XpAwardController>().claimCelebrationAwards(
      keys,
      mergeSameKey: mergeSameKey,
      oneEvent: oneEvent,
    );
  } on ProviderNotFoundException {
    return const [];
  }
}

List<XpAward> claimCelebrationXpForKind(
  BuildContext context,
  CelebrationKind kind,
) {
  return switch (kind) {
    CelebrationKind.siteDiscovered => _claimCelebrationXp(
      context,
      kSiteDiscoveryCelebrationXpKeys,
    ),
    CelebrationKind.siteIdentified => _claimCelebrationXp(
      context,
      kSiteIdentificationCelebrationXpKeys,
      mergeSameKey: true,
      oneEvent: false,
    ),
    CelebrationKind.siteDocumented => _claimCelebrationXp(
      context,
      kSiteDocumentationCelebrationXpKeys,
    ),
  };
}

class SiteCelebrationCard extends StatelessWidget {
  const SiteCelebrationCard({
    super.key,
    required this.event,
    required this.xpAwards,
  });

  final CelebrationEvent event;
  final List<XpAward> xpAwards;

  @override
  Widget build(BuildContext context) {
    final title = switch (event.kind) {
      CelebrationKind.siteDiscovered => CelebrationTitles.siteDiscovered,
      CelebrationKind.siteIdentified => CelebrationTitles.siteIdentified,
      CelebrationKind.siteDocumented => CelebrationTitles.siteDocumented,
    };
    return _SiteDiscoveryCelebrationSheet(
      site: event.site,
      siteId: event.siteId,
      title: title,
      xpAwards: xpAwards,
    );
  }
}

class _SiteDiscoveryCelebrationSheet extends StatefulWidget {
  const _SiteDiscoveryCelebrationSheet({
    this.site,
    this.siteId,
    required this.title,
    this.xpAwards = const [],
  });

  final SiteSummary? site;
  final int? siteId;
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
  late final Future<SiteSummary> _siteFuture;
  late final AnimationController _scaleController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _service = SiteService();
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
    _service.dispose();
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
