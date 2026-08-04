import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/xp_award_controller.dart';
import '../../models/profile.dart';
import '../../shell/app_navigator.dart';
import '../../shell/map_chrome_insets.dart';
import '../../shell/map_user_hud.dart';
import '../profile/profile_skill_detail_sheet.dart';
import 'xp_award_badge.dart';
import 'xp_magic_string_painter.dart';

/// Global overlay for **small-event** XP badges (distance, disguise, exploration).
///
/// Big-event XP is not shown here — it is embedded in celebration plaques.
/// See `xp_source_labels.dart` library doc.
///
/// Mounted above the root [Navigator] (via [MaterialApp.builder]) so it paints
/// in front of drawers, sheets, and dialogs. Multiple awards stack vertically;
/// each badge holds for [_holdDuration] then exits.
class XpAwardOverlay extends StatefulWidget {
  const XpAwardOverlay({super.key});

  @override
  State<XpAwardOverlay> createState() => _XpAwardOverlayState();
}

class _PlayingBadge {
  _PlayingBadge({required this.award});

  final XpAward award;
  final GlobalKey badgeKey = GlobalKey();
  AnimationController? entrance;
  AnimationController? magic;
  AnimationController? exit;
  bool dismissRequested = false;
  bool skipMagic = false;
  double dragDy = 0;
  Offset? from;
  Offset? to;
  late final int seed = award.skillId.hashCode ^ award.amount ^ award.id;
}

class _XpAwardOverlayState extends State<XpAwardOverlay>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 2);
  static const _magicDuration = Duration(milliseconds: 600);
  static const _tapDismissDelay = Duration(milliseconds: 700);
  static const _entranceDuration = Duration(milliseconds: 360);
  static const _exitDuration = Duration(milliseconds: 280);
  static const _stackGap = 8.0;
  static const _dismissDragThreshold = 28.0;
  static const _dismissVelocity = -280.0;

  XpAwardController? _awards;
  final Map<int, _PlayingBadge> _playing = {};
  final Set<int> _startedIds = {};

  bool get _hudVisible => _awards?.hudVisible ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final awards = context.read<XpAwardController>();
    if (!identical(awards, _awards)) {
      _awards?.removeListener(_onAwardsChanged);
      _awards = awards;
      _awards!.addListener(_onAwardsChanged);
    }
    _onAwardsChanged();
  }

  @override
  void dispose() {
    _awards?.removeListener(_onAwardsChanged);
    for (final playing in _playing.values) {
      playing.entrance?.dispose();
      playing.magic?.dispose();
      playing.exit?.dispose();
    }
    super.dispose();
  }

  void _onAwardsChanged() {
    if (!mounted) return;
    final active = _awards?.activeAwards ?? const <XpAward>[];
    for (final award in active) {
      if (_startedIds.add(award.id)) {
        unawaited(_play(award));
      }
    }
    setState(() {});
  }

  Future<void> _play(XpAward award) async {
    final playing = _PlayingBadge(award: award);
    // Distance-only visit chip (0 XP) — no magic-string to the XP bar.
    if (award.amount <= 0) playing.skipMagic = true;
    _playing[award.id] = playing;
    if (mounted) setState(() {});

    final entrance = AnimationController(
      vsync: this,
      duration: _entranceDuration,
    );
    playing.entrance = entrance;
    entrance.addListener(_tick);
    await entrance.forward();
    if (!mounted) return;

    await _waitHoldOrDismiss(playing);
    if (!mounted) return;

    final isLastVisible = _playing.length <= 1;
    if (!playing.dismissRequested &&
        !playing.skipMagic &&
        _hudVisible &&
        isLastVisible) {
      _captureEndpoints(playing);
      final magic = AnimationController(
        vsync: this,
        duration: _magicDuration,
      );
      playing.magic = magic;
      magic.addListener(_tick);
      await Future.any([
        magic.forward(),
        _waitUntilDismissed(playing),
      ]);
      if (!mounted) return;
      if (magic.isAnimating) magic.stop();
    } else if (playing.skipMagic && !playing.dismissRequested) {
      await _waitUntilDismissed(playing);
      if (!mounted) return;
    }

    if (playing.magic != null) {
      playing.magic!.dispose();
      playing.magic = null;
      playing.from = null;
      playing.to = null;
    }

    final exit = AnimationController(
      vsync: this,
      duration: _exitDuration,
    );
    playing.exit = exit;
    exit.addListener(_tick);
    await exit.forward();

    playing.entrance?.dispose();
    playing.exit?.dispose();
    _playing.remove(award.id);
    _startedIds.remove(award.id);
    _awards?.dismiss(award.id);
    if (mounted) setState(() {});
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _requestDismiss(_PlayingBadge playing) {
    if (playing.dismissRequested) return;
    playing.dismissRequested = true;
  }

  Future<void> _waitHoldOrDismiss(_PlayingBadge playing) async {
    final end = DateTime.now().add(_holdDuration);
    while (
        mounted && !playing.dismissRequested && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _waitUntilDismissed(_PlayingBadge playing) async {
    while (mounted && !playing.dismissRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  void _openSkillDrawer(XpAward award) {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return;

    final profile = context.read<AuthController>().currentUser;
    SkillState? skill;
    if (profile != null) {
      for (final candidate in profile.skills) {
        if (candidate.id == award.skillId) {
          skill = candidate;
          break;
        }
      }
    }
    skill ??= SkillState(
      id: award.skillId,
      name: award.skillName,
      xp: 0,
      level: 1,
      nextLevelXp: 0,
      xpToNext: 0,
      progress: 0,
    );

    showProfileSkillDetailSheet(
      navContext,
      skill: skill,
      breakdown: profile?.skillBreakdown[award.skillId],
    );
    final playing = _playing[award.id];
    if (playing == null) return;
    playing.skipMagic = true;
    Future<void>.delayed(_tapDismissDelay, () {
      if (mounted) _requestDismiss(playing);
    });
  }

  void _onVerticalDragUpdate(_PlayingBadge playing, DragUpdateDetails details) {
    final next = (playing.dragDy + details.delta.dy).clamp(-120.0, 0.0);
    if (next == playing.dragDy) return;
    setState(() => playing.dragDy = next);
  }

  void _onVerticalDragEnd(_PlayingBadge playing, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (playing.dragDy <= -_dismissDragThreshold ||
        velocity <= _dismissVelocity) {
      _requestDismiss(playing);
      return;
    }
    setState(() => playing.dragDy = 0);
  }

  void _captureEndpoints(_PlayingBadge playing) {
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;

    final badgeBox =
        playing.badgeKey.currentContext?.findRenderObject() as RenderBox?;
    final barBox = MapUserHud.xpBarKey.currentContext?.findRenderObject()
        as RenderBox?;

    Offset from;
    if (badgeBox != null && badgeBox.hasSize) {
      final global = badgeBox.localToGlobal(
        Offset(badgeBox.size.width * 0.35, badgeBox.size.height * 0.5),
      );
      from = overlayBox.globalToLocal(global);
    } else {
      final topPad = MediaQuery.paddingOf(context).top;
      from = Offset(
        48,
        _hudVisible
            ? topPad + MapChromeInsets.topRowHeight + 28
            : topPad + 36,
      );
    }

    Offset to;
    if (barBox != null && barBox.hasSize) {
      final auth = context.read<AuthController>();
      final progress =
          (auth.currentUser?.effectiveCareer.progress ?? 0.5).clamp(0.0, 1.0);
      final global = barBox.localToGlobal(
        Offset(barBox.size.width * progress, barBox.size.height * 0.5),
      );
      to = overlayBox.globalToLocal(global);
    } else {
      final topPad = MediaQuery.paddingOf(context).top;
      to = Offset(90, topPad + 52);
    }

    setState(() {
      playing.from = from;
      playing.to = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_playing.isEmpty) return const SizedBox.shrink();

    final topPad = MediaQuery.paddingOf(context).top;
    final top = _hudVisible
        ? topPad + MapChromeInsets.topRowHeight + 4
        : topPad + 8;

    // Preserve enqueue order for stable stacking (oldest on top).
    final ordered = _awards?.activeAwards
            .where((award) => _playing.containsKey(award.id))
            .map((award) => _playing[award.id]!)
            .toList() ??
        _playing.values.toList();

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final playing in ordered)
            if (_hudVisible &&
                playing.magic != null &&
                playing.from != null &&
                playing.to != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: XpMagicStringPainter(
                      from: playing.from!,
                      to: playing.to!,
                      progress: Curves.easeInOutCubic
                          .transform(playing.magic!.value),
                      seed: playing.seed,
                    ),
                  ),
                ),
              ),
          Positioned(
            top: top,
            left: _hudVisible ? 12 : 0,
            right: _hudVisible ? null : 0,
            child: Align(
              alignment:
                  _hudVisible ? Alignment.centerLeft : Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: _hudVisible
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    if (i > 0) const SizedBox(height: _stackGap),
                    _buildBadge(ordered[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(_PlayingBadge playing) {
    final entrance = playing.entrance;
    final exit = playing.exit;

    final enterT = Curves.easeOutBack.transform(entrance?.value ?? 1.0);
    final exitT = Curves.easeInCubic.transform(exit?.value ?? 0.0);
    final opacity = ((entrance?.value ?? 1.0) * (1.0 - exitT)).clamp(0.0, 1.0);
    final scale = (0.88 + 0.12 * enterT) * (1.0 - 0.06 * exitT);
    final slideY = (1.0 - enterT) * -18.0 + exitT * -28.0 + playing.dragDy;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: Transform.scale(
          alignment: _hudVisible ? Alignment.topLeft : Alignment.topCenter,
          scale: scale,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSkillDrawer(playing.award),
            onVerticalDragUpdate: (details) =>
                _onVerticalDragUpdate(playing, details),
            onVerticalDragEnd: (details) =>
                _onVerticalDragEnd(playing, details),
            child: KeyedSubtree(
              key: playing.badgeKey,
              child: XpAwardBadge(award: playing.award),
            ),
          ),
        ),
      ),
    );
  }
}
