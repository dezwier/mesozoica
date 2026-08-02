import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../models/profile.dart';
import 'profile_skill_icons.dart';

const _breakdownLabels = <String, String>{
  'sites': 'Sites discovered',
  'fossils': 'Fossils discovered',
  'active_distance': 'Active distance',
  'passive_distance': 'Passive distance',
};

const _mainParamLabels = <String, String>{
  'visibility_distance_m': 'Visibility distance',
  'discovery_chance': 'Discovery chance',
  'max_discovery_speed_kmh': 'Max discovery speed',
  'dino_count': 'Dino count',
  'fossil_count': 'Fossil count',
  'depth_weights': 'Depth weights',
  'completeness_weights': 'Completeness weights',
  'quality_weights': 'Quality weights',
};

const _toolActionLabels = <String, String>{
  'geo_compass': 'Geo Compass',
  'site_navigator': 'Site Navigator',
  'proximity_scanner': 'Proximity Scanner',
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
    isScrollControlled: true,
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
      final mainParamRows = _mainParamRowsForSkill(skill);

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Row(
                children: [
                  SkillIcon(
                    skillId: skill.id,
                    size: 36,
                    circular: true,
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
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
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
              const SizedBox(height: 20),
              Text(
                'Main params',
                style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              if (mainParamRows.isEmpty)
                Text(
                  'No global params yet',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                )
              else
                for (final row in mainParamRows) ...[
                  _MainParamRow(row: row, scheme: scheme),
                  const SizedBox(height: 12),
                ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 8),
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
          );
        },
      );
    },
  );
}

class _MainParamDisplay {
  const _MainParamDisplay({
    required this.label,
    required this.baseValue,
    this.levelNote,
    this.toolNotes = const [],
  });

  final String label;
  final String baseValue;
  final String? levelNote;
  final List<String> toolNotes;
}

class _MainParamRow extends StatelessWidget {
  const _MainParamRow({required this.row, required this.scheme});

  final _MainParamDisplay row;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              row.baseValue,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        if (row.levelNote != null) ...[
          const SizedBox(height: 4),
          Text(
            row.levelNote!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
        for (final note in row.toolNotes) ...[
          const SizedBox(height: 2),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

List<_MainParamDisplay> _mainParamRowsForSkill(SkillState skill) {
  if (!GameConfig.isLoaded) return const [];
  final domain = GameConfig.instance.skillDomain(skill.id);
  if (domain is SiteDiscoveryConfig) {
    return _siteDiscoveryRows(domain, skill.level);
  }
  if (domain is SiteSurveyConfig) {
    return _siteSurveyRows(domain, skill.level);
  }
  if (domain is SkillStubConfig) {
    if (!domain.hasMainParams) return const [];
    return [
      for (final entry in domain.mainParams.entries)
        _MainParamDisplay(
          label: _mainParamLabels[entry.key] ?? entry.key,
          baseValue: entry.value.toString(),
          levelNote: _levelNote(
            domain.levelModifiers[entry.key],
            skill.level,
          ),
        ),
    ];
  }
  return const [];
}

List<_MainParamDisplay> _siteDiscoveryRows(
  SiteDiscoveryConfig cfg,
  int skillLevel,
) {
  final toolMods = _toolModifierNotesForSkill('site_discovery');
  return [
    _MainParamDisplay(
      label: 'Visibility distance',
      baseValue: _formatMeters(cfg.visibilityDistanceM),
      levelNote: _levelNote(
        cfg.levelModifiers['visibility_distance_m'],
        skillLevel,
      ),
      toolNotes: toolMods['visibility_distance_m'] ?? const [],
    ),
    _MainParamDisplay(
      label: 'Discovery chance',
      baseValue: _formatChance(cfg.discoveryChance),
      levelNote: _levelNote(
        cfg.levelModifiers['discovery_chance'],
        skillLevel,
      ),
      toolNotes: toolMods['discovery_chance'] ?? const [],
    ),
    _MainParamDisplay(
      label: 'Max discovery speed',
      baseValue: _formatKmh(cfg.maxDiscoverySpeedKmh),
      levelNote: _levelNote(
        cfg.levelModifiers['max_discovery_speed_kmh'],
        skillLevel,
      ),
      toolNotes: toolMods['max_discovery_speed_kmh'] ?? const [],
    ),
  ];
}

List<_MainParamDisplay> _siteSurveyRows(SiteSurveyConfig cfg, int skillLevel) {
  return [
    _MainParamDisplay(
      label: 'Dino count',
      baseValue: '${cfg.dinoCount.length} tiers',
      levelNote: _levelNote(cfg.levelModifiers['dino_count'], skillLevel),
    ),
    _MainParamDisplay(
      label: 'Fossil count',
      baseValue: _formatWeightMap(cfg.fossilCount.map(
        (k, v) => MapEntry(k.toString(), v),
      )),
      levelNote: _levelNote(cfg.levelModifiers['fossil_count'], skillLevel),
    ),
    _MainParamDisplay(
      label: 'Depth weights',
      baseValue: '${cfg.depthWeights.length} buckets',
      levelNote: _levelNote(cfg.levelModifiers['depth_weights'], skillLevel),
    ),
    _MainParamDisplay(
      label: 'Completeness weights',
      baseValue: _formatWeightMap(cfg.completenessWeights),
      levelNote: _levelNote(
        cfg.levelModifiers['completeness_weights'],
        skillLevel,
      ),
    ),
    _MainParamDisplay(
      label: 'Quality weights',
      baseValue: _formatWeightMap(cfg.qualityWeights),
      levelNote: _levelNote(cfg.levelModifiers['quality_weights'], skillLevel),
    ),
  ];
}

Map<String, List<String>> _toolModifierNotesForSkill(String skillId) {
  if (!GameConfig.isLoaded) return const {};
  final tools = GameConfig.instance.toolActions;
  final out = <String, List<String>>{};
  for (final entry in {
    'geo_compass': tools.geoCompass,
    'proximity_scanner': tools.proximityScanner,
    'site_navigator': tools.siteNavigator,
  }.entries) {
    final mods = entry.value.modifiesMainParams;
    if (mods == null || !mods.affectsSkill(skillId)) continue;
    final toolName = _toolActionLabels[entry.key] ?? entry.key;
    for (final bucket in [
      (mods.paramsFor('owning', skillId), 'while owned'),
      (mods.paramsFor('using', skillId), 'while using'),
    ]) {
      for (final param in bucket.$1.entries) {
        final note = '$toolName (${bucket.$2}): ${_formatModifier(param.value)}';
        out.putIfAbsent(param.key, () => []).add(note);
      }
    }
  }
  return out;
}

String? _levelNote(List<LevelModifierEntry>? entries, int skillLevel) {
  if (entries == null || entries.isEmpty) return null;
  final applicable = entries.where((e) => e.level <= skillLevel).toList();
  if (applicable.isEmpty) {
    final next = entries.reduce((a, b) => a.level < b.level ? a : b);
    return 'Lv ${next.level}: ${_formatModifier(ParamModifier(op: next.op, value: next.value))}';
  }
  final best = applicable.reduce((a, b) => a.level > b.level ? a : b);
  return 'Lv ${best.level}: ${_formatModifier(ParamModifier(op: best.op, value: best.value))}';
}

String _formatModifier(ParamModifier mod) {
  switch (mod.op) {
    case 'replace':
      return 'set ${_formatLoose(mod.value)}';
    case 'add':
      return '+${_formatLoose(mod.value)}';
    case 'multiply':
      return '×${_formatLoose(mod.value)}';
    default:
      return '${mod.op} ${_formatLoose(mod.value)}';
  }
}

String _formatLoose(double value) {
  if (value >= 0 && value <= 1) return _formatChance(value);
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

String _formatChance(double value) {
  final pct = (value * 100);
  if (pct == pct.roundToDouble()) return '${pct.toStringAsFixed(0)}%';
  return '${pct.toStringAsFixed(1)}%';
}

String _formatMeters(double value) {
  if (value == value.roundToDouble()) return '${value.toStringAsFixed(0)} m';
  return '${value.toStringAsFixed(1)} m';
}

String _formatKmh(double value) {
  if (value == value.roundToDouble()) return '${value.toStringAsFixed(0)} km/h';
  return '${value.toStringAsFixed(1)} km/h';
}

String _formatWeightMap(Map<String, double> weights) {
  if (weights.isEmpty) return '—';
  return weights.entries
      .map((e) => '${e.key} ${_formatChance(e.value)}')
      .join(' · ');
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
