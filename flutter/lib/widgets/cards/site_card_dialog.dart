import 'package:flutter/material.dart';

import '../../models/catalog_data_source.dart';
import '../../models/site.dart';
import '../../services/site_service.dart';
import 'card_detail_sheet.dart';
import 'site_turnable_card.dart';

Future<void> showSiteCardDialog(
  BuildContext context, {
  required int siteId,
  CatalogDataSource dataSource = CatalogDataSource.archive,
  SiteService? siteService,
}) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _SiteCardSheet(
      siteId: siteId,
      dataSource: dataSource,
      siteService: siteService,
    ),
  );
}

class _SiteCardSheet extends StatefulWidget {
  const _SiteCardSheet({
    required this.siteId,
    this.dataSource = CatalogDataSource.archive,
    this.siteService,
  });

  final int siteId;
  final CatalogDataSource dataSource;
  final SiteService? siteService;

  @override
  State<_SiteCardSheet> createState() => _SiteCardSheetState();
}

class _SiteCardSheetState extends State<_SiteCardSheet> {
  late final SiteService _service;
  late final bool _ownsService;
  late final Future<SiteSummary> _siteFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.siteService == null;
    _service = widget.siteService ?? SiteService();
    _siteFuture = _service.fetchSiteById(
      widget.siteId,
      dataSource: widget.dataSource,
    );
  }

  @override
  void dispose() {
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
          return const SizedBox.shrink();
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
                    style: Theme.of(context).textTheme.bodyMedium,
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

        return CardDetailSheetContent(
          child: SiteTurnableCard(site: snapshot.data!),
        );
      },
    );
  }
}
