import 'package:flutter/material.dart';

class ToolParamsEditSheet extends StatefulWidget {
  const ToolParamsEditSheet({
    super.key,
    required this.params,
    required this.onSave,
  });

  final Map<String, dynamic> params;
  final ValueChanged<Map<String, dynamic>> onSave;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> params,
    required ValueChanged<Map<String, dynamic>> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ToolParamsEditSheet(params: params, onSave: onSave),
    );
  }

  @override
  State<ToolParamsEditSheet> createState() => _ToolParamsEditSheetState();
}

class _ToolParamsEditSheetState extends State<ToolParamsEditSheet> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final entry in widget.params.entries) {
      _controllers[entry.key] = TextEditingController(
        text: entry.value?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _buildUpdatedParams() {
    final updated = <String, dynamic>{};
    for (final entry in widget.params.entries) {
      final key = entry.key;
      final originalValue = entry.value;
      final textValue = _controllers[key]?.text.trim() ?? '';
      updated[key] = _parseWithOriginalType(textValue, originalValue);
    }
    return updated;
  }

  dynamic _parseWithOriginalType(String value, dynamic originalValue) {
    if (originalValue is bool) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    if (originalValue is int) {
      return int.tryParse(value) ?? originalValue;
    }
    if (originalValue is double) {
      return double.tryParse(value) ?? originalValue;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Edit Parameters',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.params.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final key = widget.params.keys.elementAt(index);
                return TextFormField(
                  controller: _controllers[key],
                  decoration: InputDecoration(
                    labelText: key,
                    border: const OutlineInputBorder(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  widget.onSave(_buildUpdatedParams());
                  Navigator.of(context).pop();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
