import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/site_service.dart';
import 'site_turnable_card.dart';

Future<void> showSiteCardDialog(
  BuildContext context, {
  required int siteId,
  SiteService? siteService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: _SiteCardSheet(
              siteId: siteId,
              siteService: siteService,
            ),
          ),
        ),
      );
    },
  );
}

class _SiteCardSheet extends StatefulWidget {
  const _SiteCardSheet({
    required this.siteId,
    this.siteService,
  });

  final int siteId;
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
    _siteFuture = _service.fetchSiteById(widget.siteId);
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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return FutureBuilder<SiteSummary>(
      future: _siteFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Loading site…',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
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

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: SiteTurnableCard(
              site: snapshot.data!,
              titleFontSize: 22,
            ),
          ),
        );
      },
    );
  }
}
