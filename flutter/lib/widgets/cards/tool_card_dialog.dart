import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../services/tool_service.dart';
import 'card_detail_sheet.dart';
import 'tool_turnable_card.dart';

Future<void> showToolCardDialog(
  BuildContext context, {
  int? toolId,
  ToolSummary? tool,
}) {
  assert(tool != null || toolId != null, 'Provide tool or toolId');
  return CardDetailSheet.show<void>(
    context,
    builder: (context) => _ToolCardSheet(toolId: toolId, tool: tool),
  );
}

class _ToolCardSheet extends StatefulWidget {
  const _ToolCardSheet({this.toolId, this.tool});

  final int? toolId;
  final ToolSummary? tool;

  @override
  State<_ToolCardSheet> createState() => _ToolCardSheetState();
}

class _ToolCardSheetState extends State<_ToolCardSheet> {
  final ToolService _service = ToolService();
  late final Future<ToolSummary> _toolFuture;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.tool;
    _toolFuture = preloaded != null
        ? Future<ToolSummary>.value(preloaded)
        : _service.fetchToolById(widget.toolId!);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ToolSummary>(
      future: _toolFuture,
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
                    snapshot.error?.toString() ?? 'Could not load tool.',
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
          child: ToolTurnableCard(tool: snapshot.data!),
        );
      },
    );
  }
}
