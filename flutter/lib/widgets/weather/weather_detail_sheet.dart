import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/weather_controller.dart';
import '../../models/weather_status.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../profile/profile_skill_icons.dart';
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

enum _ImpactView { skillParams, xpSources }

enum _AmbientAxis { timeOfDay, temperature, weather }

/// Full weather report + gameplay impact boxes for time, temperature, weather.
class WeatherDetailDrawer extends StatefulWidget {
  const WeatherDetailDrawer({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  static const double _cardRadius = 10;

  @override
  State<WeatherDetailDrawer> createState() => _WeatherDetailDrawerState();
}

class _WeatherDetailDrawerState extends State<WeatherDetailDrawer> {
  String? _selectedSkillId;
  _AmbientAxis _axis = _AmbientAxis.timeOfDay;

  List<LevelingSkillConfig> get _skills {
    if (!GameConfig.isLoaded) return const [];
    return GameConfig.instance.leveling.skills;
  }

  String get _skillId {
    final skills = _skills;
    if (skills.isEmpty) return 'field_survey';
    final selected = _selectedSkillId;
    if (selected != null && skills.any((s) => s.id == selected)) {
      return selected;
    }
    return skills.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.watch<WeatherController>().status;
    final skills = _skills;
    final skillId = _skillId;

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
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        children: [
                          _WeatherHero(status: status),
                          if (skills.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _SkillTabs(
                              skills: skills,
                              selectedId: skillId,
                              onChanged: (id) =>
                                  setState(() => _selectedSkillId = id),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _AmbientAxisTabs(
                            selected: _axis,
                            weatherType: status.weatherType,
                            onChanged: (axis) =>
                                setState(() => _axis = axis),
                          ),
                          const SizedBox(height: 16),
                          _selectedImpactCard(status, skillId),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _selectedImpactCard(WeatherStatus status, String skillId) {
    switch (_axis) {
      case _AmbientAxis.timeOfDay:
        return _ImpactSectionCard(
          icon: Icons.schedule,
          title: 'Time of day',
          subtitle: WeatherDisplay.timeLabelWithClock(status.weatherTime),
          groups: _impactGroupsForSkill(
            skillId,
            _weatherTimeImpactBySkill(status.weatherTime),
          ),
        );
      case _AmbientAxis.temperature:
        return _ImpactSectionCard(
          icon: Icons.thermostat_outlined,
          title: 'Temperature',
          subtitle: _tempSubtitle(status),
          groups: const _ImpactGroups(),
          emptyLabel: 'No temperature parameter impacts yet',
        );
      case _AmbientAxis.weather:
        return _ImpactSectionCard(
          icon: WeatherDisplay.weatherIcon(status.weatherType),
          title: 'Weather',
          subtitle: WeatherDisplay.weatherLabel(status.weatherType),
          groups: _impactGroupsForSkill(
            skillId,
            _weatherTypeImpactBySkill(status.weatherType),
          ),
          emptyLabel: 'No weather-type parameter impacts',
        );
    }
  }

  static String _tempSubtitle(WeatherStatus status) {
    if (status.weatherType == 'unknown' && status.observedAt == null) {
      return '—';
    }
    return '${status.temperatureC.round()}°C';
  }

  static _ImpactGroups _impactGroupsForSkill(
    String skillId,
    Map<String, _ImpactGroups> bySkill,
  ) =>
      bySkill[skillId] ?? const _ImpactGroups();

  /// Skill → param groups for [period] (drawer order; ±0% if none).
  static Map<String, _ImpactGroups> _weatherTimeImpactBySkill(String period) {
    if (!GameConfig.isLoaded) return const {};
    final game = GameConfig.instance;
    return _ambientImpactBySkill(period, [
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

  /// Skill → param groups for [weatherType] (drawer order; ±0% if none).
  static Map<String, _ImpactGroups> _weatherTypeImpactBySkill(
    String weatherType,
  ) {
    if (!GameConfig.isLoaded) return const {};
    final key = weatherType == 'sunny' ? 'clear' : weatherType;
    final game = GameConfig.instance;
    return _ambientImpactBySkill(key, [
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

  static Map<String, _ImpactGroups> _ambientImpactBySkill(
    String key,
    List<
        (
          String,
          Map<String, Map<String, List<ParamModifier>>>,
          List<String>,
          List<String>,
        )> sources,
  ) {
    final out = <String, _ImpactGroups>{};
    for (final (skillId, modifiers, skillKeys, xpKeys) in sources) {
      out[skillId] = _ImpactGroups(
        skillParams: [
          for (final paramKey in skillKeys)
            _ImpactRow(
              paramLabel: WeatherDisplay.paramLabel(paramKey),
              effect: _formatAmbientEffect(
                modifiers[paramKey]?[key] ?? const <ParamModifier>[],
              ),
            ),
        ],
        xpSources: [
          for (final paramKey in xpKeys)
            _ImpactRow(
              paramLabel: WeatherDisplay.paramLabel(paramKey),
              effect: _formatAmbientEffect(
                modifiers[paramKey]?[key] ?? const <ParamModifier>[],
              ),
            ),
        ],
      );
    }
    return out;
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

class _SkillTabs extends StatelessWidget {
  const _SkillTabs({
    required this.skills,
    required this.selectedId,
    required this.onChanged,
  });

  final List<LevelingSkillConfig> skills;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final skill in skills)
            Expanded(
              child: _SegmentTab(
                selected: skill.id == selectedId,
                onTap: () => onChanged(skill.id),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SkillIcon(skillId: skill.id, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        skill.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: skill.id == selectedId
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontWeight: skill.id == selectedId
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              height: 1.1,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbientAxisTabs extends StatelessWidget {
  const _AmbientAxisTabs({
    required this.selected,
    required this.weatherType,
    required this.onChanged,
  });

  final _AmbientAxis selected;
  final String weatherType;
  final ValueChanged<_AmbientAxis> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <(_AmbientAxis, IconData, String)>[
      (_AmbientAxis.timeOfDay, Icons.schedule, 'Time'),
      (_AmbientAxis.temperature, Icons.thermostat_outlined, 'Temp'),
      (
        _AmbientAxis.weather,
        WeatherDisplay.weatherIcon(weatherType),
        'Weather',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (axis, icon, label) in entries)
            Expanded(
              child: _SegmentTab(
                selected: axis == selected,
                onTap: () => onChanged(axis),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: axis == selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: axis == selected
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontWeight: axis == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              height: 1.1,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
    );
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
    required this.paramLabel,
    required this.effect,
  });

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
class _ImpactSectionCard extends StatefulWidget {
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
  State<_ImpactSectionCard> createState() => _ImpactSectionCardState();
}

class _ImpactSectionCardState extends State<_ImpactSectionCard> {
  _ImpactView _view = _ImpactView.skillParams;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = widget.groups;
    final hasSkill = groups.skillParams.isNotEmpty;
    final hasXp = groups.xpSources.isNotEmpty;
    final canToggle = hasSkill && hasXp;
    final view = !canToggle
        ? (hasXp && !hasSkill
            ? _ImpactView.xpSources
            : _ImpactView.skillParams)
        : _view;
    final rows = view == _ImpactView.xpSources
        ? groups.xpSources
        : groups.skillParams;

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
                Icon(widget.icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            if (canToggle) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _ImpactViewToggle(
                  selected: view,
                  onChanged: (next) => setState(() => _view = next),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (groups.isEmpty || rows.isEmpty)
              Text(
                widget.emptyLabel,
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
                        rows[i].paramLabel,
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
        ),
      ),
    );
  }
}

class _ImpactViewToggle extends StatelessWidget {
  const _ImpactViewToggle({
    required this.selected,
    required this.onChanged,
  });

  final _ImpactView selected;
  final ValueChanged<_ImpactView> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ImpactToggleSegment(
            label: 'Params',
            selected: selected == _ImpactView.skillParams,
            onTap: () => onChanged(_ImpactView.skillParams),
          ),
          _ImpactToggleSegment(
            label: 'XP',
            selected: selected == _ImpactView.xpSources,
            onTap: () => onChanged(_ImpactView.xpSources),
          ),
        ],
      ),
    );
  }
}

class _ImpactToggleSegment extends StatelessWidget {
  const _ImpactToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                height: 1.1,
              ),
        ),
      ),
    );
  }
}
