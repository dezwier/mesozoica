import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../cards/card_detail_sheet.dart';
import '../cards/site_turnable_card.dart';

Future<void> showSiteMapCardDialog(
  BuildContext context,
  SiteSummary site,
) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _SiteMapCard(site: site),
  );
}

class _SiteMapCard extends StatefulWidget {
  const _SiteMapCard({required this.site});

  final SiteSummary site;

  @override
  State<_SiteMapCard> createState() => _SiteMapCardState();
}

class _SiteMapCardState extends State<_SiteMapCard> {
  late SiteSummary _site;

  @override
  void initState() {
    super.initState();
    _site = widget.site;
  }

  void _onSiteUpdated(SiteSummary updated) {
    setState(() => _site = updated);
    context.read<map_data.MapController>().upsertSite(updated);
  }

  SiteSummary _resolvedSite(map_data.MapController map) {
    for (final site in map.geoSites) {
      if (site.siteId == _site.siteId) return site;
    }
    return _site;
  }

  @override
  Widget build(BuildContext context) {
    final map = context.watch<map_data.MapController>();
    final site = _resolvedSite(map);
    return CardDetailSheetContent(
      child: SiteTurnableCard(
        site: site,
        onSiteUpdated: _onSiteUpdated,
      ),
    );
  }
}
