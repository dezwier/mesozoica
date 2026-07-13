import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../cards/card_detail_sheet.dart';
import '../cards/site_turnable_card.dart';

Future<void> showSiteMapCardDialog(
  BuildContext context,
  SiteSummary site,
) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => CardDetailSheetContent(
      child: SiteTurnableCard(site: site),
    ),
  );
}
