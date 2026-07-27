import 'package:flutter/material.dart';

import '../../models/profile.dart';

const _breakdownLabels = <String, String>{
  'sites': 'Sites discovered',
  'fossils': 'Fossils discovered',
  'active_distance': 'Active distance',
  'passive_distance': 'Passive distance',
};

void showProfileSkillDetailSheet(
  BuildContext context, {
  required SkillState skill,
  Map<String, int>? breakdown,
}) {
  final scheme = Theme.of(context).colorScheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final rows = breakdown?.entries
              .where((entry) => entry.value > 0)
              .map(
                (entry) => (
                  _breakdownLabels[entry.key] ?? entry.key,
                  entry.value,
                ),
              )
              .toList() ??
          const [];

      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              skill.name,
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${skill.level}/99',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_formatXp(skill.xp)} / ${_formatXp(skill.nextLevelXp)} xp',
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatXp(skill.xpToNext)} to next level',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'XP sources',
                style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              for (final row in rows) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${row.$2} XP',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      );
    },
  );
}

String _formatXp(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
