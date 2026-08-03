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
                            rows: _weatherTimeImpactRows(status.weatherTime),
                          ),
                          const SizedBox(height: 5),
                          _ImpactSectionCard(
                            icon: Icons.thermostat_outlined,
                            title: 'Temperature',
                            subtitle: _tempSubtitle(status),
                            rows: const [],
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
                            rows: _weatherTypeImpactRows(status.weatherType),
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

  /// Active [weather_time_modifiers] for [period] across all skill domains.
  static List<_ImpactRow> _weatherTimeImpactRows(String period) {
    if (!GameConfig.isLoaded) return const [];
    final game = GameConfig.instance;
    return _ambientImpactRows(period, [
      ('site_discovery', game.siteDiscovery.weatherTimeModifiers),
      ('site_survey', game.siteSurvey.weatherTimeModifiers),
      for (final stub in _skillStubs(game))
        (stub.skillId, stub.weatherTimeModifiers),
    ]);
  }

  /// Active [weather_type_modifiers] for [weatherType] across all skill domains.
  static List<_ImpactRow> _weatherTypeImpactRows(String weatherType) {
    if (!GameConfig.isLoaded) return const [];
    final key = weatherType == 'sunny' ? 'clear' : weatherType;
    final game = GameConfig.instance;
    return _ambientImpactRows(key, [
      ('site_discovery', game.siteDiscovery.weatherTypeModifiers),
      ('site_survey', game.siteSurvey.weatherTypeModifiers),
      for (final stub in _skillStubs(game))
        (stub.skillId, stub.weatherTypeModifiers),
    ]);
  }

  static List<SkillStubConfig> _skillStubs(GameConfig game) => [
        game.siteClearing,
        game.fossilDetection,
        game.fossilExcavation,
        game.fossilTransport,
        game.fossilCuration,
        game.fossilPreparation,
        game.fossilAnalysis,
        game.dinosaurModelling,
        game.dinosaurMounting,
        game.academicPublishing,
      ];

  static List<_ImpactRow> _ambientImpactRows(
    String key,
    List<(String, Map<String, Map<String, List<ParamModifier>>>)> sources,
  ) {
    final skillNames = {
      for (final skill in GameConfig.instance.leveling.skills) skill.id: skill.name,
    };
    final out = <_ImpactRow>[];
    for (final (skillId, modifiers) in sources) {
      final skillName = skillNames[skillId] ?? skillId;
      for (final paramEntry in modifiers.entries) {
        for (final mod in paramEntry.value[key] ?? const <ParamModifier>[]) {
          out.add(
            _ImpactRow(
              skillName: skillName,
              paramLabel: WeatherDisplay.paramLabel(paramEntry.key),
              effect: WeatherDisplay.formatModifierShort(
                op: mod.op,
                value: mod.value,
              ),
            ),
          );
        }
      }
    }
    return out;
  }
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
    required this.rows,
    this.emptyLabel = 'No impacts right now',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_ImpactRow> rows;
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
            if (rows.isEmpty)
              Text(
                emptyLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else
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
    );
  }
}
