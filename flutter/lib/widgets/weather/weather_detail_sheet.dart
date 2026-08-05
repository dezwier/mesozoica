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
  String? _previewTime;
  String? _previewWeather;

  List<LevelingSkillConfig> get _skills {
    if (!GameConfig.isLoaded) return const [];
    // Science Hall has no weather/time impacts — omit from this report.
    return [
      for (final skill in GameConfig.instance.leveling.skills)
        if (skill.id != 'science_hall') skill,
    ];
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

  String _selectedTime(WeatherStatus status) {
    final preview = _previewTime;
    if (preview != null && WeatherDisplay.weatherTimes.contains(preview)) {
      return preview;
    }
    return status.weatherTime;
  }

  String _selectedWeather(WeatherStatus status) {
    final preview = _previewWeather;
    final normalized = preview == 'sunny' ? 'clear' : preview;
    if (normalized != null &&
        WeatherDisplay.weatherTypes.contains(normalized)) {
      return normalized;
    }
    final current =
        status.weatherType == 'sunny' ? 'clear' : status.weatherType;
    return WeatherDisplay.weatherTypes.contains(current)
        ? current
        : WeatherDisplay.weatherTypes.first;
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
        final selected = _selectedTime(status);
        return _ImpactSectionCard(
          icon: Icons.schedule,
          title: 'Time of day',
          groups: _impactGroupsForSkill(
            skillId,
            _weatherTimeImpactBySkill(selected),
          ),
          optionKeys: WeatherDisplay.optionsWithCurrentFirst(
            WeatherDisplay.weatherTimes,
            status.weatherTime,
          ),
          selectedOption: selected,
          optionLabel: WeatherDisplay.timeLabel,
          onOptionChanged: (key) => setState(() => _previewTime = key),
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
        final selected = _selectedWeather(status);
        return _ImpactSectionCard(
          icon: WeatherDisplay.weatherIcon(selected),
          title: 'Weather',
          groups: _impactGroupsForSkill(
            skillId,
            _weatherTypeImpactBySkill(selected),
          ),
          optionKeys: WeatherDisplay.optionsWithCurrentFirst(
            WeatherDisplay.weatherTypes,
            status.weatherType == 'sunny' ? 'clear' : status.weatherType,
          ),
          selectedOption: selected,
          optionLabel: WeatherDisplay.weatherLabel,
          optionIcon: WeatherDisplay.weatherIcon,
          onOptionChanged: (key) => setState(() => _previewWeather = key),
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

  /// Skill → param groups for [period] (only params affected by some period).
  static Map<String, _ImpactGroups> _weatherTimeImpactBySkill(String period) {
    if (!GameConfig.isLoaded) return const {};
    final game = GameConfig.instance;
    return _ambientImpactBySkill(
      period,
      WeatherDisplay.weatherTimes,
      [
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
      ],
    );
  }

  /// Skill → param groups for [weatherType] (only params affected by some type).
  static Map<String, _ImpactGroups> _weatherTypeImpactBySkill(
    String weatherType,
  ) {
    if (!GameConfig.isLoaded) return const {};
    final key = weatherType == 'sunny' ? 'clear' : weatherType;
    final game = GameConfig.instance;
    return _ambientImpactBySkill(
      key,
      WeatherDisplay.weatherTypes,
      [
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
      ],
    );
  }

  static List<SkillStubConfig> _skillStubs(GameConfig game) => [
        game.boneQuarry,
      ];

  static List<String> _stubSkillParamKeys(SkillStubConfig stub) => [
        for (final key in stub.mainParams.keys)
          if (!key.endsWith('_xp')) key,
      ];

  static List<String> _stubXpParamKeys(SkillStubConfig stub) => [
        for (final key in stub.mainParams.keys)
          if (key.endsWith('_xp')) key,
      ];

  static bool _modsHaveEffect(List<ParamModifier> mods) {
    if (mods.isEmpty) return false;
    for (final mod in mods) {
      if (mod.op == 'multiply' && (mod.value - 1.0).abs() < 1e-9) continue;
      if (mod.op == 'add' && mod.value.abs() < 1e-9) continue;
      return true;
    }
    return false;
  }

  static bool _paramAffectedByAny(
    Map<String, Map<String, List<ParamModifier>>> modifiers,
    String paramKey,
    List<String> optionKeys,
  ) {
    final byOption = modifiers[paramKey];
    if (byOption == null || byOption.isEmpty) return false;
    for (final option in optionKeys) {
      if (_modsHaveEffect(byOption[option] ?? const <ParamModifier>[])) {
        return true;
      }
    }
    return false;
  }

  static Map<String, _ImpactGroups> _ambientImpactBySkill(
    String key,
    List<String> allOptionKeys,
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
      final activeSkillKeys = [
        for (final paramKey in skillKeys)
          if (_paramAffectedByAny(modifiers, paramKey, allOptionKeys))
            paramKey,
      ];
      final activeXpKeys = [
        for (final paramKey in xpKeys)
          if (_paramAffectedByAny(modifiers, paramKey, allOptionKeys))
            paramKey,
      ];
      out[skillId] = _ImpactGroups(
        skillParams: [
          for (final paramKey in activeSkillKeys)
            _ImpactRow(
              paramLabel: WeatherDisplay.paramLabel(paramKey),
              effect: _formatAmbientEffect(
                modifiers[paramKey]?[key] ?? const <ParamModifier>[],
              ),
            ),
        ],
        xpSources: [
          for (final paramKey in activeXpKeys)
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
class _ImpactSectionCard extends StatelessWidget {
  const _ImpactSectionCard({
    required this.icon,
    required this.title,
    required this.groups,
    this.subtitle,
    this.emptyLabel = 'No impacts right now',
    this.optionKeys,
    this.selectedOption,
    this.optionLabel,
    this.optionIcon,
    this.onOptionChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final _ImpactGroups groups;
  final String emptyLabel;
  final List<String>? optionKeys;
  final String? selectedOption;
  final String Function(String key)? optionLabel;
  final IconData Function(String key)? optionIcon;
  final ValueChanged<String>? onOptionChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSkill = groups.skillParams.isNotEmpty;
    final hasXp = groups.xpSources.isNotEmpty;
    final optionKeys = this.optionKeys;
    final hasOptions = optionKeys != null &&
        optionKeys.isNotEmpty &&
        selectedOption != null &&
        optionLabel != null &&
        onOptionChanged != null;

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
                if (hasOptions)
                  _OptionDropdown(
                    keys: optionKeys,
                    selected: selectedOption!,
                    labelOf: optionLabel!,
                    iconOf: optionIcon,
                    onChanged: onOptionChanged!,
                  )
                else if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasSkill && !hasXp)
              Text(
                emptyLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else ...[
              if (hasSkill)
                _ImpactParamBlock(
                  title: 'Skill parameters',
                  rows: groups.skillParams,
                ),
              if (hasSkill && hasXp) ...[
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 12),
              ],
              if (hasXp)
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
    );
  }
}

class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    required this.keys,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
  });

  final List<String> keys;
  final String selected;
  final String Function(String key) labelOf;
  final IconData Function(String key)? iconOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected,
        isDense: true,
        borderRadius: BorderRadius.circular(10),
        icon: Icon(
          Icons.expand_more,
          size: 18,
          color: scheme.primary,
        ),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
        selectedItemBuilder: (context) => [
          for (final key in keys)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconOf != null) ...[
                    Icon(iconOf!(key), size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Text(labelOf(key)),
                ],
              ),
            ),
        ],
        items: [
          for (final key in keys)
            DropdownMenuItem<String>(
              value: key,
              child: Row(
                children: [
                  if (iconOf != null) ...[
                    Icon(
                      iconOf!(key),
                      size: 16,
                      color: key == selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    labelOf(key),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: key == selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

