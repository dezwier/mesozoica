import 'package:flutter/material.dart';

import '../../models/profile.dart';
import 'profile_skill_icons.dart';

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
      final skillProgress = (skill.level.clamp(1, 99) / 99.0).clamp(0.0, 1.0);
      final levelProgress = skill.progress.clamp(0.0, 1.0);

      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  skillIconFor(skill.id),
                  color: scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    skill.name,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${skill.level}/99',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SkillProgressBar(
              progress: skillProgress,
              emphasized: true,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatXp(skill.xp)} / ${_formatXp(skill.nextLevelXp)} xp',
                    style: Theme.of(sheetContext).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${_formatXp(skill.xpToNext)} left',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SkillProgressBar(
              progress: levelProgress,
              emphasized: false,
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

class _SkillProgressBar extends StatelessWidget {
  const _SkillProgressBar({
    required this.progress,
    required this.emphasized,
  });

  final double progress;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: emphasized ? 7 : 5,
        backgroundColor: scheme.onSurface.withValues(
          alpha: emphasized ? 0.08 : 0.05,
        ),
        color: scheme.primary.withValues(alpha: emphasized ? 0.8 : 0.45),
      ),
    );
  }
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
