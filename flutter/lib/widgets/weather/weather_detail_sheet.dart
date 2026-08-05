import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/weather_controller.dart';
import '../../models/weather_status.dart';
import '../common/draggable_sheet_wrapper.dart';
import 'weather_display.dart';

/// Opens the ambient weather report drawer (same height as skill / profile sheets).
void showWeatherDetailSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableSheetWrapper(
      childBuilder: (scrollController) =>
          WeatherDetailDrawer(scrollController: scrollController),
    ),
  );
}

/// Full weather report + gameplay impact boxes for time, temperature, weather.
class WeatherDetailDrawer extends StatelessWidget {
  const WeatherDetailDrawer({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  static const double _cardRadius = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.watch<WeatherController>().status;

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
                child: status == null
                    ? Center(
                        child: Text(
                          'Waiting for location…',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        children: [
                          _WeatherHero(status: status),
                          const SizedBox(height: 16),
                          _ImpactSectionCard(
                            icon: Icons.schedule,
                            title: 'Time of day',
                            subtitle: WeatherDisplay.timeLabelWithClock(
                              status.weatherTime,
                            ),
                            groups: _weatherTimeImpactGroups(
                              status.weatherTime,
                            ),
                          ),
                          const SizedBox(height: 5),
                          _ImpactSectionCard(
                            icon: Icons.thermostat_outlined,
                            title: 'Temperature',
                            subtitle: _tempSubtitle(status),
                            groups: const _ImpactGroups(),
                            emptyLabel:
                                'No temperature parameter impacts yet',
                          ),
                          const SizedBox(height: 5),
                          _ImpactSectionCard(
                            icon: WeatherDisplay.weatherIcon(
                              status.weatherType,
                            ),
                            title: 'Weather',
                            subtitle: WeatherDisplay.weatherLabel(
                              status.weatherType,
                            ),
                            groups: _weatherTypeImpactGroups(
                              status.weatherType,
                            ),
                            emptyLabel: 'No weather-type parameter impacts',
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

  static String _tempSubtitle(WeatherStatus status) {
    if (status.weatherType == 'unknown' && status.observedAt == null) {
      return '—';
    }
    return '${status.temperatureC.round()}°C';
  }

  /// All skill/XP params for [period] across domains (drawer order; ±0% if none).
  static _ImpactGroups _weatherTimeImpactGroups(String period) {
    if (!GameConfig.isLoaded) return const _ImpactGroups();
    final game = GameConfig.instance;
    return _ambientImpactGroups(period, [
      (
        'field_survey',
        game.fieldSurvey.weatherTimeModifiers,
        WeatherDisplay.fieldSurveySkillParamKeys,
        WeatherDisplay.fieldSurveyXpParamKeys,
      ),
      for (final stub in _skillStubs(game))
        (
          stub.skillId,
          stub.weatherTimeModifiers,
          _stubSkillParamKeys(stub),
          _stubXpParamKeys(stub),
        ),
    ]);
  }

  /// All skill/XP params for [weatherType] across domains (drawer order; ±0% if none).
  static _ImpactGroups _weatherTypeImpactGroups(String weatherType) {
    if (!GameConfig.isLoaded) return const _ImpactGroups();
    final key = weatherType == 'sunny' ? 'clear' : weatherType;
    final game = GameConfig.instance;
    return _ambientImpactGroups(key, [
      (
        'field_survey',
        game.fieldSurvey.weatherTypeModifiers,
        WeatherDisplay.fieldSurveySkillParamKeys,
        WeatherDisplay.fieldSurveyXpParamKeys,
      ),
      for (final stub in _skillStubs(game))
        (
          stub.skillId,
          stub.weatherTypeModifiers,
          _stubSkillParamKeys(stub),
          _stubXpParamKeys(stub),
        ),
    ]);
  }

  static List<SkillStubConfig> _skillStubs(GameConfig game) => [
        game.boneQuarry,
        game.scienceHall,
      ];

  static List<String> _stubSkillParamKeys(SkillStubConfig stub) => [
        for (final key in stub.mainParams.keys)
          if (!key.endsWith('_xp')) key,
      ];

  static List<String> _stubXpParamKeys(SkillStubConfig stub) => [
        for (final key in stub.mainParams.keys)
          if (key.endsWith('_xp')) key,
      ];

  static _ImpactGroups _ambientImpactGroups(
    String key,
    List<
        (
          String,
          Map<String, Map<String, List<ParamModifier>>>,
          List<String>,
          List<String>,
        )> sources,
  ) {
    final skillNames = {
      for (final skill in GameConfig.instance.leveling.skills)
        skill.id: skill.name,
    };
    final skillParams = <_ImpactRow>[];
    final xpSources = <_ImpactRow>[];
    for (final (skillId, modifiers, skillKeys, xpKeys) in sources) {
      final skillName = skillNames[skillId] ?? skillId;
      for (final paramKey in skillKeys) {
        skillParams.add(
          _ImpactRow(
            skillName: skillName,
            paramLabel: WeatherDisplay.paramLabel(paramKey),
            effect: _formatAmbientEffect(
              modifiers[paramKey]?[key] ?? const <ParamModifier>[],
            ),
          ),
        );
      }
      for (final paramKey in xpKeys) {
        xpSources.add(
          _ImpactRow(
            skillName: skillName,
            paramLabel: WeatherDisplay.paramLabel(paramKey),
            effect: _formatAmbientEffect(
              modifiers[paramKey]?[key] ?? const <ParamModifier>[],
            ),
          ),
        );
      }
    }
    return _ImpactGroups(skillParams: skillParams, xpSources: xpSources);
  }

  static String _formatAmbientEffect(List<ParamModifier> mods) {
    if (mods.isEmpty) return '±0%';
    return mods
        .map(
          (m) => WeatherDisplay.formatModifierShort(op: m.op, value: m.value),
        )
        .join(' · ');
  }
}

class _ImpactGroups {
  const _ImpactGroups({
    this.skillParams = const [],
    this.xpSources = const [],
  });

  final List<_ImpactRow> skillParams;
  final List<_ImpactRow> xpSources;

  bool get isEmpty => skillParams.isEmpty && xpSources.isEmpty;
}

class _ImpactRow {
  const _ImpactRow({
    required this.skillName,
    required this.paramLabel,
    required this.effect,
  });

  final String skillName;
  final String paramLabel;
  final String effect;
}

class _WeatherHero extends StatelessWidget {
  const _WeatherHero({required this.status});

  final WeatherStatus status;

  static const _overlayShadows = <Shadow>[
    Shadow(
      color: Color(0xCC000000),
      blurRadius: 14,
      offset: Offset(0, 2),
    ),
    Shadow(
      color: Color(0x99000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tempReady =
        !(status.weatherType == 'unknown' && status.observedAt == null);
    final tempText =
        tempReady ? '${status.temperatureC.round()}°' : '—';
    final asset = WeatherDisplay.assetPath(
      status.weatherType,
      weatherTime: status.weatherTime,
    );
    final radius = BorderRadius.circular(WeatherDetailDrawer._cardRadius);

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      WeatherDisplay.weatherIcon(status.weatherType),
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              )
            else
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    WeatherDisplay.weatherIcon(status.weatherType),
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x33000000),
                    Color(0xB8000000),
                  ],
                  stops: [0.42, 0.68, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    WeatherDisplay.weatherLabel(status.weatherType),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          shadows: _overlayShadows,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        tempText,
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  shadows: _overlayShadows,
                                ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Container(
                          width: 1,
                          height: 22,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      Text(
                        WeatherDisplay.timeLabelWithClock(status.weatherTime),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w600,
                                  shadows: _overlayShadows,
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile-style section card listing parameter impacts for one weather axis.
class _ImpactSectionCard extends StatelessWidget {
  const _ImpactSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.groups,
    this.emptyLabel = 'No impacts right now',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _ImpactGroups groups;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeatherDetailDrawer._cardRadius),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius:
              BorderRadius.circular(WeatherDetailDrawer._cardRadius),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              Text(
                emptyLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else ...[
              if (groups.skillParams.isNotEmpty)
                _ImpactParamBlock(
                  title: 'Skill parameters',
                  rows: groups.skillParams,
                ),
              if (groups.skillParams.isNotEmpty &&
                  groups.xpSources.isNotEmpty)
                const SizedBox(height: 14),
              if (groups.xpSources.isNotEmpty)
                _ImpactParamBlock(
                  title: 'XP sources',
                  rows: groups.xpSources,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImpactParamBlock extends StatelessWidget {
  const _ImpactParamBlock({
    required this.title,
    required this.rows,
  });

  final String title;
  final List<_ImpactRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${rows[i].skillName} · ${rows[i].paramLabel}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rows[i].effect,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: rows[i].effect == '±0%'
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
