import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/ridge_glass_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../controllers/weather_controller.dart';
import '../../models/profile.dart';
import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../services/api_client.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../weather/weather_display.dart';
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
  'site_discovery_xp': 'Site discovery XP',
  'active_km_xp': 'Active km XP',
  'passive_km_xp': 'Passive km XP',
  'fossil_discovery_xp': 'Fossil discovery XP',
  'dino_accuracy': 'Dinosaur accuracy',
  'fossil_accuracy': 'Fossil accuracy',
  'completeness_accuracy': 'Completeness accuracy',
  'quality_accuracy': 'Quality accuracy',
  'depth_accuracy': 'Depth accuracy',
};

const _cardRadius = 10.0;

enum _ParamFormat { chance, meters, kmh, xp, plain }

void showProfileSkillDetailSheet(
  BuildContext context, {
  required SkillState skill,
  Map<String, int>? breakdown,
}) {
  final toolBindings = _toolModBindings(context);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableSheetWrapper(
      childBuilder: (scrollController) => _SkillDetailDrawer(
        skill: skill,
        breakdown: breakdown,
        toolBindings: toolBindings,
        scrollController: scrollController,
      ),
    ),
  );
}

class _SkillDetailDrawer extends StatelessWidget {
  const _SkillDetailDrawer({
    required this.skill,
    required this.toolBindings,
    required this.scrollController,
    this.breakdown,
  });

  final SkillState skill;
  final Map<String, int>? breakdown;
  final List<ToolModBinding> toolBindings;
  final ScrollController scrollController;

  SkillState _liveSkill(Profile? profile) {
    if (profile == null) return skill;
    for (final candidate in profile.skills) {
      if (candidate.id == skill.id) return candidate;
    }
    return skill;
  }

  Map<String, int>? _liveBreakdown(Profile? profile) {
    if (profile == null) return breakdown;
    return profile.skillBreakdown[skill.id] ?? breakdown;
  }

  Future<void> _onEditXp(BuildContext context, SkillState skill) async {
    final controller = TextEditingController(text: '${skill.xp}');
    final xp = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Set ${skill.name} XP'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'XP',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final parsed = int.tryParse(value.trim());
              if (parsed == null) return;
              Navigator.of(ctx).pop(parsed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null) return;
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (xp == null || !context.mounted) return;

    try {
      await context.read<AuthController>().setSkillXp(
            skillId: skill.id,
            xp: xp,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${skill.name} XP set to $xp')),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to set skill XP: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final weather = context.watch<WeatherController>();
    final weatherTime = weather.weatherTime;
    final weatherType = weather.status?.weatherType;
    final liveSkill = _liveSkill(auth.currentUser);
    final liveBreakdown = _liveBreakdown(auth.currentUser);
    final showAdminUi = auth.showAdminUi;
    final scheme = Theme.of(context).colorScheme;
    final xpRows = liveBreakdown?.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => (
                _breakdownLabels[entry.key] ?? entry.key,
                entry.value,
              ),
            )
            .toList() ??
        const <(String, int)>[];
    final paramRows = _mainParamRowsForSkill(
      liveSkill,
      toolBindings: toolBindings,
      weatherTime: weatherTime,
      weatherType: weatherType,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  children: [
                    _SkillHud(
                      skill: liveSkill,
                      onEditXp: showAdminUi
                          ? () => _onEditXp(context, liveSkill)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (xpRows.isNotEmpty) ...[
                      _SkillSectionCard(
                        icon: Icons.bolt_outlined,
                        title: 'XP sources',
                        child: Column(
                          children: [
                            for (var i = 0; i < xpRows.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      xpRows[i].$1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    '${xpRows[i].$2} XP',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    _SkillSectionCard(
                      icon: Icons.tune,
                      title: 'Skill parameters',
                      child: paramRows.isEmpty
                          ? Text(
                              'No global params yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < paramRows.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 14),
                                  _MainParamRow(
                                    row: paramRows[i],
                                    scheme: scheme,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Big skill mark + title / level / dual progress — profile analogue of map HUD.
class _SkillHud extends StatelessWidget {
  const _SkillHud({
    required this.skill,
    this.onEditXp,
  });

  final SkillState skill;
  final VoidCallback? onEditXp;

  static const double _iconSize = 92;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final skillProgress = (skill.level.clamp(1, 99) / 99.0).clamp(0.0, 1.0);
    final levelProgress = skill.progress.clamp(0.0, 1.0);
    final muted = scheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _iconSize + 6,
          height: _iconSize + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 4,
                top: 0,
                child: SkillIcon(
                  skillId: skill.id,
                  size: _iconSize,
                  circular: true,
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                    border: Border.all(
                      color: scheme.surface,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    '${skill.level}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      skill.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                    ),
                  ),
                  if (onEditXp != null)
                    IconButton(
                      onPressed: onEditXp,
                      icon: const Icon(Icons.settings, size: 20),
                      tooltip: 'Set XP',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Level',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${skill.level}/99',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _HudProgressBar(progress: skillProgress, emphasized: true),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatXp(skill.xp)} / ${_formatXp(skill.nextLevelXp)} XP',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                    ),
                  ),
                  Text(
                    '${_formatXp(skill.xpToNext)} left',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: muted.withValues(alpha: 0.75),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _HudProgressBar(progress: levelProgress, emphasized: false),
            ],
          ),
        ),
      ],
    );
  }
}

class _HudProgressBar extends StatelessWidget {
  const _HudProgressBar({
    required this.progress,
    required this.emphasized,
  });

  final double progress;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: scheme.outline.withValues(alpha: emphasized ? 0.4 : 0.28),
          width: 0.75,
        ),
        color: scheme.onSurface.withValues(alpha: 0.04),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: emphasized ? 6 : 4,
          backgroundColor: Colors.transparent,
          color: scheme.primary.withValues(alpha: emphasized ? 0.9 : 0.5),
        ),
      ),
    );
  }
}

class _SkillSectionCard extends StatelessWidget {
  const _SkillSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

List<ToolModBinding> _toolModBindings(BuildContext context) {
  try {
    final catalog = context.read<ToolCatalogController>().items;
    ToolSession? activeSession;
    String? activeActionKey;
    String? activeToolName;

    final ridge = context.read<RidgeGlassController>();
    if (ridge.isActive) {
      activeSession = ridge.session;
      activeActionKey = ridge.session?.actionKey ?? 'ridge_glass';
      activeToolName = ridge.tool?.name;
    } else {
      final guidance = context.read<GuidanceSessionController>();
      if (guidance.isActive) {
        activeSession = guidance.session;
        activeActionKey =
            guidance.kind?.actionKey ?? guidance.session?.actionKey;
        activeToolName = guidance.tool?.name;
      }
    }

    return toolModBindingsFromInstances(
      catalog: catalog,
      activeSession: activeSession,
      activeActionKey: activeActionKey,
      activeToolName: activeToolName,
    );
  } catch (_) {
    return const [];
  }
}

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
  required List<ToolModBinding> toolBindings,
  String? weatherTime,
  String? weatherType,
}) {
  if (!GameConfig.isLoaded) return const [];
  final domain = GameConfig.instance.skillDomain(skill.id);
  if (domain is SiteDiscoveryConfig) {
    return _siteDiscoveryRows(
      domain,
      skill.level,
      toolBindings: toolBindings,
      weatherTime: weatherTime,
      weatherType: weatherType,
    );
  }
  if (domain is SiteSurveyConfig) {
    return _siteSurveyRows(
      domain,
      skill.level,
      toolBindings: toolBindings,
      weatherTime: weatherTime,
      weatherType: weatherType,
    );
  }
  if (domain is SkillStubConfig) {
    if (!domain.hasMainParams) return const [];
    return [
      for (final entry in domain.mainParams.entries)
        if (entry.value is num)
          _resolveScalarParam(
            label: _mainParamLabels[entry.key] ?? entry.key,
            paramKey: entry.key,
            skillId: domain.skillId,
            base: (entry.value as num).toDouble(),
            levelEntries: domain.levelModifiers[entry.key],
            weatherTimeMods: domain.weatherTimeModifiers[entry.key],
            weatherTime: weatherTime,
            weatherTypeMods: domain.weatherTypeModifiers[entry.key],
            weatherType: weatherType,
            skillLevel: skill.level,
            format: entry.key.endsWith('_xp')
                ? _ParamFormat.xp
                : _ParamFormat.plain,
            clampUnit: false,
            toolBindings: toolBindings,
          )
        else
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
  required List<ToolModBinding> toolBindings,
  String? weatherTime,
  String? weatherType,
}) {
  return [
    _resolveScalarParam(
      label: 'Visibility distance',
      paramKey: 'visibility_distance_m',
      skillId: 'site_discovery',
      base: cfg.visibilityDistanceM,
      levelEntries: cfg.levelModifiers['visibility_distance_m'],
      weatherTimeMods: cfg.weatherTimeModifiers['visibility_distance_m'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['visibility_distance_m'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.meters,
      clampUnit: false,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Discovery chance',
      paramKey: 'discovery_chance',
      skillId: 'site_discovery',
      base: cfg.discoveryChance,
      levelEntries: cfg.levelModifiers['discovery_chance'],
      weatherTimeMods: cfg.weatherTimeModifiers['discovery_chance'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['discovery_chance'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Max discovery speed',
      paramKey: 'max_discovery_speed_kmh',
      skillId: 'site_discovery',
      base: cfg.maxDiscoverySpeedKmh,
      levelEntries: cfg.levelModifiers['max_discovery_speed_kmh'],
      weatherTimeMods: cfg.weatherTimeModifiers['max_discovery_speed_kmh'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['max_discovery_speed_kmh'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.kmh,
      clampUnit: false,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Site discovery XP',
      paramKey: 'site_discovery_xp',
      skillId: 'site_discovery',
      base: cfg.siteDiscoveryXp,
      levelEntries: cfg.levelModifiers['site_discovery_xp'],
      weatherTimeMods: cfg.weatherTimeModifiers['site_discovery_xp'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['site_discovery_xp'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.xp,
      clampUnit: false,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Active km XP',
      paramKey: 'active_km_xp',
      skillId: 'site_discovery',
      base: cfg.activeKmXp,
      levelEntries: cfg.levelModifiers['active_km_xp'],
      weatherTimeMods: cfg.weatherTimeModifiers['active_km_xp'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['active_km_xp'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.xp,
      clampUnit: false,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Passive km XP',
      paramKey: 'passive_km_xp',
      skillId: 'site_discovery',
      base: cfg.passiveKmXp,
      levelEntries: cfg.levelModifiers['passive_km_xp'],
      weatherTimeMods: cfg.weatherTimeModifiers['passive_km_xp'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['passive_km_xp'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.xp,
      clampUnit: false,
      toolBindings: toolBindings,
    ),
  ];
}

List<_MainParamDisplay> _siteSurveyRows(
  SiteSurveyConfig cfg,
  int skillLevel, {
  required List<ToolModBinding> toolBindings,
  String? weatherTime,
  String? weatherType,
}) {
  final mp = cfg.mainParams;
  // Accuracy scalars first (level/tool resolvable), then fixed global
  // distribution tables (not subject to multipliers).
  return [
    _resolveScalarParam(
      label: 'Dinosaur accuracy',
      paramKey: 'dino_accuracy',
      skillId: 'site_survey',
      base: mp.dinoAccuracy,
      levelEntries: cfg.levelModifiers['dino_accuracy'],
      weatherTimeMods: cfg.weatherTimeModifiers['dino_accuracy'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['dino_accuracy'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Fossil accuracy',
      paramKey: 'fossil_accuracy',
      skillId: 'site_survey',
      base: mp.fossilAccuracy,
      levelEntries: cfg.levelModifiers['fossil_accuracy'],
      weatherTimeMods: cfg.weatherTimeModifiers['fossil_accuracy'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['fossil_accuracy'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Completeness accuracy',
      paramKey: 'completeness_accuracy',
      skillId: 'site_survey',
      base: mp.completenessAccuracy,
      levelEntries: cfg.levelModifiers['completeness_accuracy'],
      weatherTimeMods: cfg.weatherTimeModifiers['completeness_accuracy'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['completeness_accuracy'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Quality accuracy',
      paramKey: 'quality_accuracy',
      skillId: 'site_survey',
      base: mp.qualityAccuracy,
      levelEntries: cfg.levelModifiers['quality_accuracy'],
      weatherTimeMods: cfg.weatherTimeModifiers['quality_accuracy'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['quality_accuracy'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
    _resolveScalarParam(
      label: 'Depth accuracy',
      paramKey: 'depth_accuracy',
      skillId: 'site_survey',
      base: mp.depthAccuracy,
      levelEntries: cfg.levelModifiers['depth_accuracy'],
      weatherTimeMods: cfg.weatherTimeModifiers['depth_accuracy'],
      weatherTime: weatherTime,
      weatherTypeMods: cfg.weatherTypeModifiers['depth_accuracy'],
      weatherType: weatherType,
      skillLevel: skillLevel,
      format: _ParamFormat.chance,
      clampUnit: true,
      toolBindings: toolBindings,
    ),
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
  Map<String, List<ParamModifier>>? weatherTimeMods,
  String? weatherTime,
  Map<String, List<ParamModifier>>? weatherTypeMods,
  String? weatherType,
  required int skillLevel,
  required _ParamFormat format,
  required bool clampUnit,
  required List<ToolModBinding> toolBindings,
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

  if (weatherTime != null && weatherTimeMods != null) {
    for (final mod in weatherTimeMods[weatherTime] ?? const <ParamModifier>[]) {
      value = _applyModifier(value, mod);
      parts.add('$weatherTime ${_formatModifierShort(mod, format)}');
      affected = true;
    }
  }

  final typeKey = weatherType == 'sunny' ? 'clear' : weatherType;
  if (typeKey != null && weatherTypeMods != null) {
    for (final mod in weatherTypeMods[typeKey] ?? const <ParamModifier>[]) {
      value = _applyModifier(value, mod);
      parts.add('$typeKey ${_formatModifierShort(mod, format)}');
      affected = true;
    }
  }

  for (final toolMod in _activeToolModsForParam(
    skillId: skillId,
    paramKey: paramKey,
    toolBindings: toolBindings,
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
  required List<ToolModBinding> toolBindings,
}) {
  final out = <_ActiveToolMod>[];
  for (final binding in toolBindings) {
    final mods = binding.mods;
    if (!mods.affectsSkill(skillId)) continue;
    if (binding.applyOwning) {
      final owning = mods.paramsFor('owning', skillId)[paramKey];
      if (owning != null) {
        out.add(
          _ActiveToolMod(
            toolName: binding.toolName,
            whenLabel: 'owned',
            mod: owning,
          ),
        );
      }
    }
    if (binding.applyUsing) {
      final using = mods.paramsFor('using', skillId)[paramKey];
      if (using != null) {
        out.add(
          _ActiveToolMod(
            toolName: binding.toolName,
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
      return WeatherDisplay.formatModifierShort(op: op, value: value);
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
    case _ParamFormat.xp:
      if (value == value.roundToDouble()) return '${value.toStringAsFixed(0)} XP';
      return '${value.toStringAsFixed(1)} XP';
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
