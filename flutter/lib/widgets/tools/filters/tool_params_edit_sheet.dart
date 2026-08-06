import 'package:flutter/material.dart';

class ToolParamsEditSheet extends StatefulWidget {
  const ToolParamsEditSheet({
    super.key,
    required this.params,
    this.editableKeys,
    this.labels = const {},
    required this.onSave,
  });

  final Map<String, dynamic> params;

  /// When set, only these keys are shown/edited in the modal.
  /// Dotted paths (e.g. `a.b.c`) edit nested map values.
  final List<String>? editableKeys;

  /// Optional display labels keyed by editable key / path.
  final Map<String, String> labels;
  final ValueChanged<Map<String, dynamic>> onSave;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> params,
    List<String>? editableKeys,
    Map<String, String> labels = const {},
    required ValueChanged<Map<String, dynamic>> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ToolParamsEditSheet(
        params: params,
        editableKeys: editableKeys,
        labels: labels,
        onSave: onSave,
      ),
    );
  }

  @override
  State<ToolParamsEditSheet> createState() => _ToolParamsEditSheetState();
}

class _ToolParamsEditSheetState extends State<ToolParamsEditSheet> {
  final Map<String, TextEditingController> _controllers = {};
  late final List<String> _editableKeys;

  @override
  void initState() {
    super.initState();
    final preferred = widget.editableKeys ?? widget.params.keys.toList();
    // Keep declared edit keys even when a value is missing (seed empty field).
    _editableKeys = preferred.isNotEmpty
        ? List<String>.from(preferred)
        : widget.params.keys.toList(growable: false);

    for (final key in _editableKeys) {
      final value = _readPath(widget.params, key);
      _controllers[key] = TextEditingController(text: value?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Full params map with edits applied (preserves non-edited keys/nests).
  Map<String, dynamic> _buildUpdatedParams() {
    final updated = _deepCopy(widget.params);
    for (final key in _editableKeys) {
      final originalValue = _readPath(widget.params, key);
      final textValue = _controllers[key]?.text.trim() ?? '';
      final parsed = _parseWithOriginalType(textValue, originalValue);
      _writePath(updated, key, parsed);
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
    if (originalValue is double || originalValue is num) {
      return double.tryParse(value) ?? (originalValue as num).toDouble();
    }
    if (originalValue == null && value.isNotEmpty) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(value);
      if (asDouble != null) return asDouble;
    }
    return value;
  }

  String _labelFor(String key) =>
      widget.labels[key] ?? (key.contains('.') ? key.split('.').last : key);

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
          if (_editableKeys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No editable parameters for this tool.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _editableKeys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final key = _editableKeys[index];
                  return TextFormField(
                    controller: _controllers[key],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _labelFor(key),
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

dynamic _readPath(Map<String, dynamic> root, String path) {
  if (!path.contains('.')) return root[path];
  dynamic cur = root;
  for (final part in path.split('.')) {
    if (cur is! Map) return null;
    cur = cur[part];
  }
  return cur;
}

void _writePath(Map<String, dynamic> root, String path, dynamic value) {
  if (!path.contains('.')) {
    root[path] = value;
    return;
  }
  final parts = path.split('.');
  Map<String, dynamic> cur = root;
  for (var i = 0; i < parts.length - 1; i++) {
    final part = parts[i];
    final next = cur[part];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      cur[part] = copy;
      cur = copy;
    } else {
      final created = <String, dynamic>{};
      cur[part] = created;
      cur = created;
    }
  }
  cur[parts.last] = value;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  for (final entry in source.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      out[entry.key] = _deepCopy(value);
    } else if (value is Map) {
      out[entry.key] = _deepCopy(Map<String, dynamic>.from(value));
    } else if (value is List) {
      out[entry.key] = value.map((item) {
        if (item is Map<String, dynamic>) return _deepCopy(item);
        if (item is Map) return _deepCopy(Map<String, dynamic>.from(item));
        return item;
      }).toList();
    } else {
      out[entry.key] = value;
    }
  }
  return out;
}
