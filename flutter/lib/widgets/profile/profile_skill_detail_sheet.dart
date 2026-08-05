import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/main_param_buff_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../controllers/weather_controller.dart';
import '../../models/disguise_tool_kind.dart';
import '../../models/main_param_buff_kind.dart';
import '../../models/profile.dart';
import '../../models/tool.dart';
import '../../models/tool_session.dart';
import '../../services/api_client.dart';
import '../../utils/xp_source_labels.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../weather/weather_display.dart';
import 'profile_skill_icons.dart';

/// Maps XP-source main_param keys → skill_breakdown keys.
const _xpSourceBreakdownKeys = <String, String>{
  'discover_site_xp': 'discover_site',
  'discover_site_as_first_xp': 'discover_site_as_first',
  'explore_100m_actively_xp': 'explore_100m_actively',
  'explore_1km_passively_xp': 'explore_1km_passively',
  'locate_fossil_in_situ_xp': 'locate_fossil_in_situ',
  'disguise_of_site_xp': 'disguise_of_site',
  'document_progress_xp': 'document_progress',
  'document_site_xp': 'document_site',
  'identify_site_xp': 'identify_site',
  'document_site_as_first_xp': 'document_site_as_first',
};

const _mainParamLabels = <String, String>{
  'discovery_distance_m': 'Discovery distance',
  'discovery_chance': 'Discovery chance',
  'discovery_max_speed_kmh': 'Discovery max speed',
  'discover_site_xp': 'Discover site',
  'discover_site_as_first_xp': 'Discover site as first',
  'explore_100m_actively_xp': 'Explore 100m actively',
  'explore_1km_passively_xp': 'Explore 1km passively',
  'locate_fossil_in_situ_xp': 'Locate fossil in situ',
  'disguise_of_site_xp': 'Disguise of site',
  'document_progress_xp': 'Document progress',
  'document_site_xp': 'Document site',
  'identify_site_xp': 'Identify site',
  'document_site_as_first_xp': 'Document site as first',
  'rival_discovery_chance': 'Rival discovery chance',
  'documentation_distance_m': 'Documentation distance',
  'documentation_genera': 'Documentation genera',
  'documentation_fossil': 'Documentation fossil',
  'documentation_completeness': 'Documentation completeness',
  'documentation_preservation': 'Documentation preservation',
  'documentation_depth': 'Documentation depth',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${skill.name} XP set to $xp')));
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to set skill XP: $error')));
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
    final breakdownTotals = <String, int>{
      if (liveBreakdown != null)
        for (final entry in liveBreakdown.entries)
          if (entry.value > 0) entry.key: entry.value,
    };
    final paramGroups = _mainParamRowsForSkill(
      liveSkill,
      toolBindings: toolBindings,
      weatherTime: weatherTime,
      weatherType: weatherType,
    );
    final xpSourceRows = paramGroups.xpSources;
    final skillParamRows = paramGroups.skillParams;
    final xpRows = _mergedXpSourceRows(
      xpSourceRows: xpSourceRows,
      breakdownTotals: breakdownTotals,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    _SkillSectionCard(
                      icon: Icons.tune,
                      title: 'Skill parameters',
                      child: skillParamRows.isEmpty
                          ? Text(
                              'No global params yet',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (
                                  var i = 0;
                                  i < skillParamRows.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(height: 14),
                                  _MainParamRow(
                                    row: skillParamRows[i],
                                    scheme: scheme,
                                  ),
                                ],
                              ],
                            ),
                    ),
                    if (xpRows.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _XpSourcesSection(rows: xpRows, scheme: scheme),
                    ],
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

class _XpSourceMergedRow {
  const _XpSourceMergedRow({
    required this.label,
    required this.valueText,
    required this.totalXp,
    this.overallDeltaPct,
    this.factors = const [],
  });

  final String label;
  final String valueText;
  final int totalXp;
  final double? overallDeltaPct;
  final List<_ParamFactor> factors;
}

const _breakdownTooltipWidth = 240.0;

enum _XpSourceColumn { value, total }

class _XpSourcesSection extends StatefulWidget {
  const _XpSourcesSection({required this.rows, required this.scheme});

  final List<_XpSourceMergedRow> rows;
  final ColorScheme scheme;

  @override
  State<_XpSourcesSection> createState() => _XpSourcesSectionState();
}

class _XpSourcesSectionState extends State<_XpSourcesSection> {
  _XpSourceColumn _column = _XpSourceColumn.value;

  @override
  Widget build(BuildContext context) {
    final showValue = _column == _XpSourceColumn.value;
    return _SkillSectionCard(
      icon: Icons.bolt_outlined,
      title: 'XP sources',
      titleTrailing: _XpSourceColumnToggle(
        selected: _column,
        onChanged: (column) => setState(() => _column = column),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _MainParamRow(
              row: _MainParamDisplay(
                label: widget.rows[i].label,
                effectiveValue: showValue
                    ? widget.rows[i].valueText
                    : '${widget.rows[i].totalXp} XP',
                overallDeltaPct: showValue
                    ? widget.rows[i].overallDeltaPct
                    : null,
                factors: showValue ? widget.rows[i].factors : const [],
              ),
              scheme: widget.scheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _XpSourceColumnToggle extends StatelessWidget {
  const _XpSourceColumnToggle({
    required this.selected,
    required this.onChanged,
  });

  final _XpSourceColumn selected;
  final ValueChanged<_XpSourceColumn> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _XpSourceToggleSegment(
            label: 'Value',
            selected: selected == _XpSourceColumn.value,
            onTap: () => onChanged(_XpSourceColumn.value),
          ),
          _XpSourceToggleSegment(
            label: 'Total',
            selected: selected == _XpSourceColumn.total,
            onTap: () => onChanged(_XpSourceColumn.total),
          ),
        ],
      ),
    );
  }
}

class _XpSourceToggleSegment extends StatelessWidget {
  const _XpSourceToggleSegment({
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
          color: selected ? scheme.surface : Colors.transparent,
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

List<_XpSourceMergedRow> _mergedXpSourceRows({
  required List<_MainParamDisplay> xpSourceRows,
  required Map<String, int> breakdownTotals,
}) {
  final usedBreakdownKeys = <String>{};
  final rows = <_XpSourceMergedRow>[];

  for (final source in xpSourceRows) {
    final breakdownKey = source.paramKey == null
        ? null
        : _xpSourceBreakdownKeys[source.paramKey!];
    if (breakdownKey != null) usedBreakdownKeys.add(breakdownKey);
    rows.add(
      _XpSourceMergedRow(
        label: source.label,
        valueText: source.effectiveValue,
        totalXp: breakdownKey == null
            ? 0
            : (breakdownTotals[breakdownKey] ?? 0),
        overallDeltaPct: source.overallDeltaPct,
        factors: source.factors,
      ),
    );
  }

  // Orphan breakdown totals with no matching XP-source param.
  final leftovers =
      breakdownTotals.entries
          .where((e) => !usedBreakdownKeys.contains(e.key))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in leftovers) {
    rows.add(
      _XpSourceMergedRow(
        label: xpSourceLabel(entry.key),
        valueText: '—',
        totalXp: entry.value,
      ),
    );
  }
  return rows;
}

/// Big skill mark + title / level / dual progress — profile analogue of map HUD.
class _SkillHud extends StatelessWidget {
  const _SkillHud({required this.skill, this.onEditXp});

  final SkillState skill;
  final VoidCallback? onEditXp;

  static const double _iconSize = 104;

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
                    border: Border.all(color: scheme.surface, width: 2),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
  const _HudProgressBar({required this.progress, required this.emphasized});

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
    this.titleTrailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? titleTrailing;

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
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (titleTrailing != null) ...[
                  const SizedBox(width: 8),
                  titleTrailing!,
                ],
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

    final buff = context.read<MainParamBuffController>();
    if (buff.isActive) {
      activeSession = buff.session;
      activeActionKey = buff.session?.actionKey ?? buff.kind?.actionKey;
      activeToolName = buff.tool?.name ?? buff.kind?.toolName;
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

class _ParamFactor {
  const _ParamFactor({required this.label, required this.deltaText});

  final String label;
  final String deltaText;
}

class _MainParamDisplay {
  const _MainParamDisplay({
    required this.label,
    required this.effectiveValue,
    this.paramKey,
    this.overallDeltaPct,
    this.factors = const [],
  });

  final String label;
  final String? paramKey;

  /// The resolved value shown on the right.
  final String effectiveValue;

  /// Overall change vs base as a percent (null when unmodified or base is 0).
  final double? overallDeltaPct;

  /// Per-factor lines for the tap breakdown tooltip.
  final List<_ParamFactor> factors;
}

class _MainParamRow extends StatefulWidget {
  const _MainParamRow({required this.row, required this.scheme});

  final _MainParamDisplay row;
  final ColorScheme scheme;

  @override
  State<_MainParamRow> createState() => _MainParamRowState();
}

class _MainParamRowState extends State<_MainParamRow> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _toggleBreakdown() {
    if (_overlay != null) {
      _removeOverlay();
      return;
    }
    final factors = widget.row.factors;
    if (factors.isEmpty) return;

    final overlay = Overlay.of(context);
    final scheme = widget.scheme;

    _overlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: Material(
                elevation: 6,
                color: scheme.surfaceContainerHigh,
                shadowColor: scheme.shadow.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: _breakdownTooltipWidth,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < factors.length; i++) ...[
                          if (i > 0) const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  factors[i].label,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurface,
                                        height: 1.3,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                factors[i].deltaText,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: _deltaColor(
                                        factors[i].deltaText,
                                        scheme,
                                      ),
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final scheme = widget.scheme;
    final body = Theme.of(context).textTheme.bodyMedium;
    final valueStyle = body?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
    final deltaPct = row.overallDeltaPct ?? 0.0;
    final showBadge = row.factors.isNotEmpty;
    final rounded = deltaPct.round();
    final isZero = rounded == 0;
    const positiveColor = Color(0xFF2E7D32);
    const negativeColor = Color(0xFFC62828);
    final badgeColor = isZero
        ? scheme.onSurfaceVariant
        : (rounded > 0 ? positiveColor : negativeColor);

    Widget? deltaBadge;
    if (showBadge) {
      deltaBadge = CompositedTransformTarget(
        link: _link,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleBreakdown,
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: isZero ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: badgeColor.withValues(alpha: isZero ? 0.22 : 0.35),
                  width: 0.75,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatSignedPctNumber(deltaPct),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: badgeColor.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: Text(row.label, style: body)),
        Text(row.effectiveValue, style: valueStyle),
        if (deltaBadge != null) ...[const SizedBox(width: 8), deltaBadge],
      ],
    );
  }
}

Color _deltaColor(String deltaText, ColorScheme scheme) {
  final trimmed = deltaText.trimLeft();
  if (trimmed.startsWith('x') || trimmed.startsWith('×')) {
    final mult = double.tryParse(trimmed.substring(1));
    if (mult != null) {
      if (mult > 1.0 + 1e-12) return const Color(0xFF2E7D32);
      if (mult < 1.0 - 1e-12) return const Color(0xFFC62828);
    }
    return scheme.onSurfaceVariant;
  }
  if (trimmed.startsWith('+')) return const Color(0xFF2E7D32);
  if (trimmed.startsWith('-') && !trimmed.startsWith('→')) {
    return const Color(0xFFC62828);
  }
  return scheme.onSurfaceVariant;
}

String _formatSignedPctNumber(double pct) {
  final rounded = pct.round();
  if (rounded == 0) return '±0%';
  return rounded > 0 ? '+$rounded%' : '$rounded%';
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

class _SkillParamGroups {
  const _SkillParamGroups({
    this.xpSources = const [],
    this.skillParams = const [],
  });

  final List<_MainParamDisplay> xpSources;
  final List<_MainParamDisplay> skillParams;
}

_SkillParamGroups _mainParamRowsForSkill(
  SkillState skill, {
  required List<ToolModBinding> toolBindings,
  String? weatherTime,
  String? weatherType,
}) {
  if (!GameConfig.isLoaded) return const _SkillParamGroups();
  final domain = GameConfig.instance.skillDomain(skill.id);
  if (domain is FieldSurveyConfig) {
    return _fieldSurveyRows(
      domain,
      skill.level,
      toolBindings: toolBindings,
      weatherTime: weatherTime,
      weatherType: weatherType,
    );
  }
  if (domain is SkillStubConfig) {
    if (!domain.hasMainParams) return const _SkillParamGroups();
    final xpSources = <_MainParamDisplay>[];
    final skillParams = <_MainParamDisplay>[];
    for (final entry in domain.mainParams.entries) {
      final row = entry.value is num
          ? _resolveScalarParam(
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
          : _MainParamDisplay(
              label: _mainParamLabels[entry.key] ?? entry.key,
              effectiveValue: entry.value.toString(),
            );
      if (entry.key.endsWith('_xp')) {
        xpSources.add(row);
      } else {
        skillParams.add(row);
      }
    }
    return _SkillParamGroups(xpSources: xpSources, skillParams: skillParams);
  }
  return const _SkillParamGroups();
}

_SkillParamGroups _fieldSurveyRows(
  FieldSurveyConfig cfg,
  int skillLevel, {
  required List<ToolModBinding> toolBindings,
  String? weatherTime,
  String? weatherType,
}) {
  final mp = cfg.mainParams;
  return _SkillParamGroups(
    skillParams: [
      _resolveScalarParam(
        label: 'Discovery distance',
        paramKey: 'discovery_distance_m',
        skillId: 'field_survey',
        base: cfg.discoveryDistanceM,
        levelEntries: cfg.levelModifiers['discovery_distance_m'],
        weatherTimeMods: cfg.weatherTimeModifiers['discovery_distance_m'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['discovery_distance_m'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.meters,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Discovery chance',
        paramKey: 'discovery_chance',
        skillId: 'field_survey',
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
        label: 'Discovery max speed',
        paramKey: 'discovery_max_speed_kmh',
        skillId: 'field_survey',
        base: cfg.discoveryMaxSpeedKmh,
        levelEntries: cfg.levelModifiers['discovery_max_speed_kmh'],
        weatherTimeMods: cfg.weatherTimeModifiers['discovery_max_speed_kmh'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['discovery_max_speed_kmh'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.kmh,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation distance',
        paramKey: 'documentation_distance_m',
        skillId: 'field_survey',
        base: mp.documentationDistanceM,
        levelEntries: cfg.levelModifiers['documentation_distance_m'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_distance_m'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_distance_m'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.meters,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Rival discovery chance',
        paramKey: 'rival_discovery_chance',
        skillId: 'field_survey',
        base: mp.rivalDiscoveryChance,
        levelEntries: cfg.levelModifiers['rival_discovery_chance'],
        weatherTimeMods: cfg.weatherTimeModifiers['rival_discovery_chance'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['rival_discovery_chance'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.plain,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation genera',
        paramKey: 'documentation_genera',
        skillId: 'field_survey',
        base: mp.documentationGenera,
        levelEntries: cfg.levelModifiers['documentation_genera'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_genera'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_genera'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.chance,
        clampUnit: true,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation fossil',
        paramKey: 'documentation_fossil',
        skillId: 'field_survey',
        base: mp.documentationFossil,
        levelEntries: cfg.levelModifiers['documentation_fossil'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_fossil'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_fossil'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.chance,
        clampUnit: true,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation completeness',
        paramKey: 'documentation_completeness',
        skillId: 'field_survey',
        base: mp.documentationCompleteness,
        levelEntries: cfg.levelModifiers['documentation_completeness'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_completeness'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_completeness'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.chance,
        clampUnit: true,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation preservation',
        paramKey: 'documentation_preservation',
        skillId: 'field_survey',
        base: mp.documentationPreservation,
        levelEntries: cfg.levelModifiers['documentation_preservation'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_preservation'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_preservation'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.chance,
        clampUnit: true,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Documentation depth',
        paramKey: 'documentation_depth',
        skillId: 'field_survey',
        base: mp.documentationDepth,
        levelEntries: cfg.levelModifiers['documentation_depth'],
        weatherTimeMods: cfg.weatherTimeModifiers['documentation_depth'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['documentation_depth'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.chance,
        clampUnit: true,
        toolBindings: toolBindings,
      ),
    ],
    xpSources: [
      _resolveScalarParam(
        label: 'Discover site',
        paramKey: 'discover_site_xp',
        skillId: 'field_survey',
        base: cfg.discoverSiteXp,
        levelEntries: cfg.levelModifiers['discover_site_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['discover_site_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['discover_site_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Discover site as first',
        paramKey: 'discover_site_as_first_xp',
        skillId: 'field_survey',
        base: cfg.discoverSiteAsFirstXp,
        levelEntries: cfg.levelModifiers['discover_site_as_first_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['discover_site_as_first_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['discover_site_as_first_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Explore 100m actively',
        paramKey: 'explore_100m_actively_xp',
        skillId: 'field_survey',
        base: cfg.explore100mActivelyXp,
        levelEntries: cfg.levelModifiers['explore_100m_actively_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['explore_100m_actively_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['explore_100m_actively_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Explore 1km passively',
        paramKey: 'explore_1km_passively_xp',
        skillId: 'field_survey',
        base: cfg.explore1kmPassivelyXp,
        levelEntries: cfg.levelModifiers['explore_1km_passively_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['explore_1km_passively_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['explore_1km_passively_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Identify site',
        paramKey: 'identify_site_xp',
        skillId: 'field_survey',
        base: mp.identifySiteXp,
        levelEntries: cfg.levelModifiers['identify_site_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['identify_site_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['identify_site_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Document progress',
        paramKey: 'document_progress_xp',
        skillId: 'field_survey',
        base: mp.documentProgressXp,
        levelEntries: cfg.levelModifiers['document_progress_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['document_progress_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['document_progress_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Document site',
        paramKey: 'document_site_xp',
        skillId: 'field_survey',
        base: mp.documentSiteXp,
        levelEntries: cfg.levelModifiers['document_site_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['document_site_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['document_site_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Document site as first',
        paramKey: 'document_site_as_first_xp',
        skillId: 'field_survey',
        base: mp.documentSiteAsFirstXp,
        levelEntries: cfg.levelModifiers['document_site_as_first_xp'],
        weatherTimeMods: cfg.weatherTimeModifiers['document_site_as_first_xp'],
        weatherTime: weatherTime,
        weatherTypeMods: cfg.weatherTypeModifiers['document_site_as_first_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
      _resolveScalarParam(
        label: 'Disguise of site',
        paramKey: 'disguise_of_site_xp',
        skillId: 'field_survey',
        base: mp.disguiseOfSiteXp,
        levelEntries: cfg.levelModifiers['disguise_of_site_xp'],
        weatherTimeMods:
            cfg.weatherTimeModifiers['disguise_of_site_xp'],
        weatherTime: weatherTime,
        weatherTypeMods:
            cfg.weatherTypeModifiers['disguise_of_site_xp'],
        weatherType: weatherType,
        skillLevel: skillLevel,
        format: _ParamFormat.xp,
        clampUnit: false,
        toolBindings: toolBindings,
      ),
    ],
  );
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
  // YAML base + level → skill "base level" shown in the drawer / tooltip.
  var levelBase = base;
  final levelMod = _applicableLevelModifier(levelEntries, skillLevel);
  if (levelMod != null) {
    levelBase = _applyModifier(levelBase, levelMod);
  }

  final changeFactors = <_ParamFactor>[];
  var value = levelBase;

  void applyStep(String factorLabel, Object mod) {
    final before = value;
    value = _applyModifier(value, mod);
    changeFactors.add(
      _ParamFactor(
        label: _factorLabel(factorLabel, mod),
        deltaText: _formatStepDelta(
          before: before,
          after: value,
          mod: mod,
          format: format,
        ),
      ),
    );
  }

  if (weatherTime != null && weatherTimeMods != null) {
    for (final mod in weatherTimeMods[weatherTime] ?? const <ParamModifier>[]) {
      applyStep(WeatherDisplay.timeLabel(weatherTime), mod);
    }
  }

  final typeKey = weatherType == 'sunny' ? 'clear' : weatherType;
  if (typeKey != null && weatherTypeMods != null) {
    for (final mod in weatherTypeMods[typeKey] ?? const <ParamModifier>[]) {
      applyStep(WeatherDisplay.weatherLabel(typeKey), mod);
    }
  }

  for (final toolMod in _activeToolModsForParam(
    skillId: skillId,
    paramKey: paramKey,
    toolBindings: toolBindings,
  )) {
    applyStep(toolMod.toolName, toolMod.mod);
  }

  if (clampUnit) {
    value = value.clamp(0.0, 1.0);
  }

  final factors = <_ParamFactor>[
    _ParamFactor(
      label: 'Base (level $skillLevel)',
      deltaText: _formatScalar(levelBase, format),
    ),
    ...changeFactors,
  ];

  var overallDeltaPct = 0.0;
  if ((value - levelBase).abs() > 1e-12 && levelBase.abs() > 1e-12) {
    overallDeltaPct = ((value - levelBase) / levelBase) * 100.0;
  }

  return _MainParamDisplay(
    label: label,
    paramKey: paramKey,
    effectiveValue: _formatScalar(value, format),
    overallDeltaPct: overallDeltaPct,
    factors: factors,
  );
}

String _modOp(Object mod) =>
    mod is ParamModifier ? mod.op : (mod as LevelModifierEntry).op;

double _modValue(Object mod) =>
    mod is ParamModifier ? mod.value : (mod as LevelModifierEntry).value;

String _factorLabel(String baseLabel, Object mod) {
  if (_modOp(mod) == 'multiply') return '$baseLabel multiplier';
  return baseLabel;
}

/// e.g. 0.6 → `x0.6`, 1.5 → `x1.5`, 2 → `x2`.
String _formatMultiplyFactor(double value) {
  if (value == value.roundToDouble()) return 'x${value.toStringAsFixed(0)}';
  var s = value.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return 'x$s';
}

String _formatStepDelta({
  required double before,
  required double after,
  required Object mod,
  required _ParamFormat format,
}) {
  final op = _modOp(mod);
  final modValue = _modValue(mod);

  if (op == 'multiply') {
    return _formatMultiplyFactor(modValue);
  }
  if (op == 'replace') {
    return '→ ${_formatScalar(after, format)}';
  }
  if (before.abs() > 1e-12) {
    return _formatSignedPctNumber(((after - before) / before) * 100.0);
  }
  return _formatModifierShort(mod, format);
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
    // Site-scoped disguise covers never rewrite the global skill number.
    if (DisguiseToolKind.matchesActionKey(binding.actionKey)) continue;
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
  final op = mod is ParamModifier ? mod.op : (mod as LevelModifierEntry).op;
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
  final op = _modOp(mod);
  final value = _modValue(mod);
  switch (op) {
    case 'replace':
      return '→ ${_formatScalar(value, format)}';
    case 'add':
      final formatted = _formatScalar(value.abs(), format);
      return value >= 0 ? '+$formatted' : '-$formatted';
    case 'multiply':
      return _formatMultiplyFactor(value);
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
      if (value == value.roundToDouble())
        return '${value.toStringAsFixed(0)} XP';
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
