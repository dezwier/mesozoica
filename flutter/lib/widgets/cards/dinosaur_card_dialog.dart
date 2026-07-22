import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../services/dinosaur_service.dart';
import 'card_detail_sheet.dart';
import 'dinosaur_turnable_card.dart';

Future<void> showDinosaurCardDialog(
  BuildContext context, {
  required int dinosaurId,
}) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _DinosaurCardSheet(dinosaurId: dinosaurId),
  );
}

class _DinosaurCardSheet extends StatefulWidget {
  const _DinosaurCardSheet({required this.dinosaurId});

  final int dinosaurId;

  @override
  State<_DinosaurCardSheet> createState() => _DinosaurCardSheetState();
}

class _DinosaurCardSheetState extends State<_DinosaurCardSheet> {
  final DinosaurService _service = DinosaurService();
  late final Future<DinosaurSummary> _dinosaurFuture;

  @override
  void initState() {
    super.initState();
    _dinosaurFuture = _service.fetchDinosaurById(widget.dinosaurId);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DinosaurSummary>(
      future: _dinosaurFuture,
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
                    snapshot.error?.toString() ?? 'Could not load dinosaur.',
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
          child: DinosaurTurnableCard(dinosaur: snapshot.data!),
        );
      },
    );
  }
}
