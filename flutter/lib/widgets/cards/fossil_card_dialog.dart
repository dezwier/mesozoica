import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../services/fossil_service.dart';
import 'card_detail_sheet.dart';
import 'fossil_turnable_card.dart';

Future<void> showFossilCardDialog(
  BuildContext context, {
  required int fossilId,
  FossilService? fossilService,
}) {
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _FossilCardSheet(
      fossilId: fossilId,
      fossilService: fossilService,
    ),
  );
}

class _FossilCardSheet extends StatefulWidget {
  const _FossilCardSheet({
    required this.fossilId,
    this.fossilService,
  });

  final int fossilId;
  final FossilService? fossilService;

  @override
  State<_FossilCardSheet> createState() => _FossilCardSheetState();
}

class _FossilCardSheetState extends State<_FossilCardSheet> {
  late final FossilService _service;
  late final bool _ownsService;
  late final Future<FossilSummary> _fossilFuture;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
    _fossilFuture = _service.fetchFossilById(widget.fossilId);
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
    return FutureBuilder<FossilSummary>(
      future: _fossilFuture,
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
                        'Loading fossil…',
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
                    snapshot.error?.toString() ?? 'Could not load fossil.',
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
          child: FossilTurnableCard(fossil: snapshot.data!),
        );
      },
    );
  }
}
