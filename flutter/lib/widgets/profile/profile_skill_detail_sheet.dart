import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../models/guidance_tool_kind.dart';
import '../../models/profile.dart';
import '../../models/tool.dart';
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

enum _ParamFormat { chance, meters, kmh, plain }

void showProfileSkillDetailSheet(
  BuildContext context, {
  required SkillState skill,
  Map<String, int>? breakdown,
}) {
  final ownedActionKeys = _ownedGuidanceActionKeys(context);
  final activeActionKey = _activeGuidanceActionKey(context);

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
      final mainParamRows = _mainParamRowsForSkill(
        skill,
        ownedActionKeys: ownedActionKeys,
        activeActionKey: activeActionKey,
      );

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

Set<String> _ownedGuidanceActionKeys(BuildContext context) {
  final out = <String>{};
  try {
    final catalog = context.read<ToolCatalogController>();
    for (final tool in catalog.items) {
      if (!_toolIsOwned(tool)) continue;
      final kind = GuidanceToolKind.tryParseToolName(tool.name);
      if (kind != null) out.add(kind.actionKey);
    }
  } catch (_) {
    // Provider unavailable (e.g. tests).
  }
  return out;
}

String? _activeGuidanceActionKey(BuildContext context) {
  try {
    final guidance = context.read<GuidanceSessionController>();
    if (!guidance.isActive) return null;
    return guidance.kind?.actionKey ?? guidance.session?.actionKey;
  } catch (_) {
    return null;
  }
}

bool _toolIsOwned(ToolSummary tool) =>
    tool.isOwned || tool.ownedOccurrences.isNotEmpty;

class _DistEntry {
  const _DistEntry({required this.label, required this.value});

  final String label;
  final String value;
}

class _MainParamDisplay {
  const _MainParamDisplay({
    required this.label,
    this.effectiveValue,
    this.calculation,
    this.distribution,
  }) : assert(effectiveValue != null || distribution != null);

  final String label;

  /// Scalar params: the resolved value shown on the right.
  final String? effectiveValue;

  /// Small-print breakdown when tools/levels affect the value; null if base-only.
  final String? calculation;

  /// Distribution params: stacked label/value rows under the title.
  final List<_DistEntry>? distribution;
}

class _MainParamRow extends StatelessWidget {
  const _MainParamRow({required this.row, required this.scheme});

  final _MainParamDisplay row;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        );
    final valueStyle = body?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
    final distValueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          height: 1.35,
        );

    final dist = row.distribution;
    if (dist != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(row.label, style: body?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final entry in dist)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text(entry.label, style: small)),
                  const SizedBox(width: 12),
                  Text(entry.value, style: distValueStyle),
                ],
              ),
            ),
          if (row.calculation != null) ...[
            const SizedBox(height: 4),
            Text(row.calculation!, style: small),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(row.label, style: body)),
            Text(row.effectiveValue!, style: valueStyle),
          ],
        ),
        if (row.calculation != null) ...[
          const SizedBox(height: 4),
          Text(row.calculation!, style: small),
        ],
      ],
    );
  }
}

class _ActiveToolMod {
  const _ActiveToolMod({
    required this.toolName,
    required this.whenLabel,
    required this.mod,
  });

  final String toolName;
  final String whenLabel;
  final ParamModifier mod;
}

List<_MainParamDisplay> _mainParamRowsForSkill(
  SkillState skill, {
  required Set<String> ownedActionKeys,
  required String? activeActionKey,
}) {
  if (!GameConfig.isLoaded) return const [];
  final domain = GameConfig.instance.skillDomain(skill.id);
  if (domain is SiteDiscoveryConfig) {
    return _siteDiscoveryRows(
      domain,
      skill.level,
      ownedActionKeys: ownedActionKeys,
      activeActionKey: activeActionKey,
    );
  }
  if (domain is SiteSurveyConfig) {
    return _siteSurveyRows(domain);
  }
  if (domain is SkillStubConfig) {
    if (!domain.hasMainParams) return const [];
    return [
      for (final entry in domain.mainParams.entries)
        _MainParamDisplay(
          label: _mainParamLabels[entry.key] ?? entry.key,
          effectiveValue: entry.value.toString(),
        ),
    ];
  }
  return const [];
}

List<_MainParamDisplay> _siteDiscoveryRows(
  SiteDiscoveryConfig cfg,
  int skillLevel, {
  required Set<String> ownedActionKeys,
  required String? activeActionKey,
}) {
  return [
    _resolveScalarParam(
      label: 'Visibility distance',
      paramKey: 'visibility_distance_m',
      skillId: 'site_discovery',
      base: cfg.visibilityDistanceM,
      levelEntries: cfg.levelModifiers['visibility_distance_m'],
      skillLevel: skillLevel,
      format: _ParamFormat.meters,
      clampUnit: false,
      ownedActionKeys: ownedActionKeys,
      activeActionKey: activeActionKey,
    ),
    _resolveScalarParam(
      label: 'Discovery chance',
      paramKey: 'discovery_chance',
      skillId: 'site_discovery',
      base: cfg.discoveryChance,
      levelEntries: cfg.levelModifiers['discovery_chance'],
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      ownedActionKeys: ownedActionKeys,
      activeActionKey: activeActionKey,
    ),
    _resolveScalarParam(
      label: 'Max discovery speed',
      paramKey: 'max_discovery_speed_kmh',
      skillId: 'site_discovery',
      base: cfg.maxDiscoverySpeedKmh,
      levelEntries: cfg.levelModifiers['max_discovery_speed_kmh'],
      skillLevel: skillLevel,
      format: _ParamFormat.kmh,
      clampUnit: false,
      ownedActionKeys: ownedActionKeys,
      activeActionKey: activeActionKey,
    ),
  ];
}

List<_MainParamDisplay> _siteSurveyRows(SiteSurveyConfig cfg) {
  // Weight/threshold tables: stacked rows, not a single cramped line.
  return [
    _MainParamDisplay(
      label: 'Dino count',
      distribution: _dinoCountEntries(cfg.dinoCount),
    ),
    _MainParamDisplay(
      label: 'Fossil count',
      distribution: [
        for (final e in cfg.fossilCount.entries)
          _DistEntry(label: '${e.key}', value: _formatChance(e.value)),
      ],
    ),
    _MainParamDisplay(
      label: 'Depth',
      distribution: [
        for (final b in cfg.depthWeights)
          _DistEntry(
            label: _formatDepthRange(b.minCm, b.maxCm),
            value: _formatChance(b.weight),
          ),
      ],
    ),
    _MainParamDisplay(
      label: 'Completeness',
      distribution: [
        for (final e in cfg.completenessWeights.entries)
          _DistEntry(
            label: _humanizeKey(e.key),
            value: _formatChance(e.value),
          ),
      ],
    ),
    _MainParamDisplay(
      label: 'Quality',
      distribution: [
        for (final e in cfg.qualityWeights.entries)
          _DistEntry(
            label: _humanizeKey(e.key),
            value: _formatChance(e.value),
          ),
      ],
    ),
  ];
}

List<_DistEntry> _dinoCountEntries(List<DinoCountThreshold> tiers) {
  final out = <_DistEntry>[];
  var prev = 0.0;
  for (final tier in tiers) {
    final lo = prev;
    final hi = tier.maxOdd;
    out.add(
      _DistEntry(
        label: _formatOddRange(lo, hi),
        value: '${tier.count}',
      ),
    );
    prev = hi;
  }
  return out;
}

String _formatOddRange(double lo, double hi) {
  final loPct = _formatChance(lo);
  final hiPct = _formatChance(hi);
  if (lo <= 0) return '≤ $hiPct';
  return '$loPct – $hiPct';
}

String _formatDepthRange(int minCm, int maxCm) {
  if (minCm == 0 && maxCm == 0) return 'Surface';
  if (minCm == maxCm) return '$minCm cm';
  return '$minCm–$maxCm cm';
}

String _humanizeKey(String key) {
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

_MainParamDisplay _resolveScalarParam({
  required String label,
  required String paramKey,
  required String skillId,
  required double base,
  required List<LevelModifierEntry>? levelEntries,
  required int skillLevel,
  required _ParamFormat format,
  required bool clampUnit,
  required Set<String> ownedActionKeys,
  required String? activeActionKey,
}) {
  final parts = <String>['base ${_formatScalar(base, format)}'];
  var value = base;
  var affected = false;

  final levelMod = _applicableLevelModifier(levelEntries, skillLevel);
  if (levelMod != null) {
    value = _applyModifier(value, levelMod);
    parts.add('level ${_formatModifierShort(levelMod, format)}');
    affected = true;
  }

  for (final toolMod in _activeToolModsForParam(
    skillId: skillId,
    paramKey: paramKey,
    ownedActionKeys: ownedActionKeys,
    activeActionKey: activeActionKey,
  )) {
    value = _applyModifier(value, toolMod.mod);
    parts.add(
      '${toolMod.toolName} (${toolMod.whenLabel}) '
      '${_formatModifierShort(toolMod.mod, format)}',
    );
    affected = true;
  }

  if (clampUnit) {
    value = value.clamp(0.0, 1.0);
  }

  return _MainParamDisplay(
    label: label,
    effectiveValue: _formatScalar(value, format),
    calculation: affected ? parts.join(' · ') : null,
  );
}

List<_ActiveToolMod> _activeToolModsForParam({
  required String skillId,
  required String paramKey,
  required Set<String> ownedActionKeys,
  required String? activeActionKey,
}) {
  if (!GameConfig.isLoaded) return const [];
  final tools = GameConfig.instance.toolActions;
  final out = <_ActiveToolMod>[];

  for (final kind in GuidanceToolKind.values) {
    final cfg = tools.guidanceConfigFor(kind.actionKey);
    final mods = cfg.modifiesMainParams;
    if (mods == null || !mods.affectsSkill(skillId)) continue;

    // Owning: only if player owns this tool.
    if (ownedActionKeys.contains(kind.actionKey)) {
      final owning = mods.paramsFor('owning', skillId)[paramKey];
      if (owning != null) {
        out.add(
          _ActiveToolMod(
            toolName: kind.toolName,
            whenLabel: 'owned',
            mod: owning,
          ),
        );
      }
    }

    // Using: only while this tool session is active.
    if (activeActionKey == kind.actionKey) {
      final using = mods.paramsFor('using', skillId)[paramKey];
      if (using != null) {
        out.add(
          _ActiveToolMod(
            toolName: kind.toolName,
            whenLabel: 'using',
            mod: using,
          ),
        );
      }
    }
  }
  return out;
}

LevelModifierEntry? _applicableLevelModifier(
  List<LevelModifierEntry>? entries,
  int skillLevel,
) {
  if (entries == null || entries.isEmpty) return null;
  final applicable = entries.where((e) => e.level <= skillLevel).toList();
  if (applicable.isEmpty) return null;
  return applicable.reduce((a, b) => a.level > b.level ? a : b);
}

double _applyModifier(double base, Object mod) {
  final op = mod is ParamModifier
      ? mod.op
      : (mod as LevelModifierEntry).op;
  final value = mod is ParamModifier
      ? mod.value
      : (mod as LevelModifierEntry).value;
  switch (op) {
    case 'replace':
      return value;
    case 'add':
      return base + value;
    case 'multiply':
      return base * value;
    default:
      return base;
  }
}

String _formatModifierShort(Object mod, _ParamFormat format) {
  final op = mod is ParamModifier
      ? mod.op
      : (mod as LevelModifierEntry).op;
  final value = mod is ParamModifier
      ? mod.value
      : (mod as LevelModifierEntry).value;
  switch (op) {
    case 'replace':
      return '→ ${_formatScalar(value, format)}';
    case 'add':
      final formatted = _formatScalar(value.abs(), format);
      return value >= 0 ? '+$formatted' : '-$formatted';
    case 'multiply':
      if (value == value.roundToDouble()) {
        return '×${value.toStringAsFixed(0)}';
      }
      return '×${value.toStringAsFixed(2)}';
    default:
      return '$op ${_formatScalar(value, format)}';
  }
}

String _formatScalar(double value, _ParamFormat format) {
  switch (format) {
    case _ParamFormat.chance:
      return _formatChance(value);
    case _ParamFormat.meters:
      return _formatMeters(value);
    case _ParamFormat.kmh:
      return _formatKmh(value);
    case _ParamFormat.plain:
      if (value == value.roundToDouble()) return value.toStringAsFixed(0);
      return value.toStringAsFixed(2);
  }
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
