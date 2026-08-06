import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
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
    builder: (context) =>
        _FossilCardSheet(fossilId: fossilId, fossilService: fossilService),
  );
}

class _FossilCardSheet extends StatefulWidget {
  const _FossilCardSheet({required this.fossilId, this.fossilService});

  final int fossilId;
  final FossilService? fossilService;

  @override
  State<_FossilCardSheet> createState() => _FossilCardSheetState();
}

class _FossilCardSheetState extends State<_FossilCardSheet> {
  late final FossilService _service;
  late final bool _ownsService;
  Future<FossilSummary>? _fossilFuture;
  CatalogDataSource? _loadedForSource;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
  }

  void _ensureLoaded(CatalogDataSource source) {
    if (_loadedForSource == source && _fossilFuture != null) return;
    _loadedForSource = source;
    _fossilFuture = _service.fetchFossilById(
      widget.fossilId,
      dataSource: source,
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
    final source = context.watch<CatalogModeController>().dataSource;
    _ensureLoaded(source);

    return FutureBuilder<FossilSummary>(
      future: _fossilFuture,
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
