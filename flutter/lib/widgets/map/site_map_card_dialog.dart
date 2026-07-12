import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../cards/site_turnable_card.dart';

Future<void> showSiteMapCardDialog(
  BuildContext context,
  SiteSummary site,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: SiteTurnableCard(
                  site: site,
                  titleFontSize: 22,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
