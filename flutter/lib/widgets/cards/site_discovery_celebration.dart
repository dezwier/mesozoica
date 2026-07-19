import 'package:flutter/material.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import 'card_detail_sheet.dart';
import 'site_turnable_card.dart';

/// Celebration overlay after proximity (or notification-tap) discovery.
Future<void> showSiteDiscoveryCelebration(
  BuildContext context, {
  SiteSummary? site,
  int? siteId,
  SiteService? siteService,
}) {
  assert(site != null || siteId != null);
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _SiteDiscoveryCelebrationSheet(
      site: site,
      siteId: siteId,
      siteService: siteService,
    ),
  );
}

class _SiteDiscoveryCelebrationSheet extends StatefulWidget {
  const _SiteDiscoveryCelebrationSheet({
    this.site,
    this.siteId,
    this.siteService,
  });

  final SiteSummary? site;
  final int? siteId;
  final SiteService? siteService;

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
      duration: const Duration(milliseconds: 520),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Site discovered!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                SiteTurnableCard(
                  site: snapshot.data!,
                  autoFlipOnce: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
