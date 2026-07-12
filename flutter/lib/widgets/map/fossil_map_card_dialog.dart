import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../cards/fossil_turnable_card.dart';

Future<void> showFossilMapCardDialog(
  BuildContext context,
  FossilSummary fossil,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: FossilTurnableCard(
                  fossil: fossil,
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
