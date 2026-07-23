import 'package:flutter/material.dart';

/// Which field-world scopes to wipe in an admin purge.
class FieldDataPurgeSelection {
  const FieldDataPurgeSelection({
    this.userSites = true,
    this.userFossils = true,
    this.sites = true,
    this.fossils = true,
    this.missionEvents = true,
    this.missions = true,
  });

  final bool userSites;
  final bool userFossils;
  final bool sites;
  final bool fossils;
  final bool missionEvents;
  final bool missions;

  bool get hasAny =>
      userSites ||
      userFossils ||
      sites ||
      fossils ||
      missionEvents ||
      missions;

  FieldDataPurgeSelection copyWith({
    bool? userSites,
    bool? userFossils,
    bool? sites,
    bool? fossils,
    bool? missionEvents,
    bool? missions,
  }) {
    return FieldDataPurgeSelection(
      userSites: userSites ?? this.userSites,
      userFossils: userFossils ?? this.userFossils,
      sites: sites ?? this.sites,
      fossils: fossils ?? this.fossils,
      missionEvents: missionEvents ?? this.missionEvents,
      missions: missions ?? this.missions,
    );
  }
}

/// Confirmation dialog for wiping selected procedural field world data.
class FieldDataPurgeDialog extends StatefulWidget {
  const FieldDataPurgeDialog({super.key});

  static Future<FieldDataPurgeSelection?> confirm(BuildContext context) async {
    return showDialog<FieldDataPurgeSelection>(
      context: context,
      builder: (ctx) => const FieldDataPurgeDialog(),
    );
  }

  @override
  State<FieldDataPurgeDialog> createState() => _FieldDataPurgeDialogState();
}

class _FieldDataPurgeDialogState extends State<FieldDataPurgeDialog> {
  FieldDataPurgeSelection _selection = const FieldDataPurgeSelection();

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Delete field data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose what to permanently delete. Archive data is kept.\n'
              'This cannot be undone.',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.userSites,
              onChanged: (value) => setState(() {
                _selection = _selection.copyWith(userSites: value ?? false);
              }),
              title: const Text('User field progress'),
              subtitle: const Text('user_site'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.userFossils,
              onChanged: (value) => setState(() {
                _selection = _selection.copyWith(userFossils: value ?? false);
              }),
              title: const Text('User fossil progress'),
              subtitle: const Text('user_fossil'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.sites,
              onChanged: (value) => setState(() {
                _selection = _selection.copyWith(sites: value ?? false);
              }),
              title: const Text('Field sites'),
              subtitle: const Text('site (field)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.fossils,
              onChanged: (value) => setState(() {
                _selection = _selection.copyWith(fossils: value ?? false);
              }),
              title: const Text('Field fossils'),
              subtitle: const Text('fossil (field)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.missionEvents,
              onChanged: (value) => setState(() {
                _selection =
                    _selection.copyWith(missionEvents: value ?? false);
              }),
              title: const Text('Mission events'),
              subtitle: const Text('tool_mission_event'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _selection.missions,
              onChanged: (value) => setState(() {
                _selection = _selection.copyWith(missions: value ?? false);
              }),
              title: const Text('Tool missions'),
              subtitle: const Text('tool_mission'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _selection.hasAny
              ? () => Navigator.pop(context, _selection)
              : null,
          child: Text(
            'Delete',
            style: TextStyle(color: _selection.hasAny ? errorColor : null),
          ),
        ),
      ],
    );
  }
}
