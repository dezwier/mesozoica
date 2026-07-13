import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../cards/card_detail_sheet.dart';
import '../cards/fossil_turnable_card.dart';

Future<void> showFossilMapCardDialog(
  BuildContext context,
  FossilSummary fossil,
) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => CardDetailSheetContent(
      child: FossilTurnableCard(fossil: fossil),
    ),
  );
}
