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

/// Global XP-earned overlay: badge under (or at) the profile HUD + magic string.
///
/// Mounted above the root [Navigator] (via [MaterialApp.builder]) so it paints
/// in front of drawers, sheets, and dialogs.
class XpAwardOverlay extends StatefulWidget {
  const XpAwardOverlay({super.key});

  @override
  State<XpAwardOverlay> createState() => _XpAwardOverlayState();
}

class _XpAwardOverlayState extends State<XpAwardOverlay>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 7500);
  static const _magicDuration = Duration(milliseconds: 900);
  static const _tapDismissDelay = Duration(milliseconds: 1100);
  static const _dismissDragThreshold = 28.0;
  static const _dismissVelocity = -280.0;

  final GlobalKey _badgeKey = GlobalKey();

  XpAwardController? _awards;
  bool _pumping = false;
  bool _dismissRequested = false;
  bool _skipMagic = false;
  double _dragDy = 0;

  AnimationController? _entrance;
  AnimationController? _magic;
  AnimationController? _exit;

  XpAward? _playing;
  Offset? _from;
  Offset? _to;
  int _seed = 0;

  bool get _hudVisible => _awards?.hudVisible ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final awards = context.read<XpAwardController>();
    if (!identical(awards, _awards)) {
      _awards?.removeListener(_onAwardsChanged);
      _awards = awards;
      _awards!.addListener(_onAwardsChanged);
      _onAwardsChanged();
    }
  }

  @override
  void dispose() {
    _awards?.removeListener(_onAwardsChanged);
    _entrance?.dispose();
    _magic?.dispose();
    _exit?.dispose();
    super.dispose();
  }

  void _onAwardsChanged() {
    if (_playing != null && mounted) setState(() {});
    if (!_pumping) {
      _pumpQueue();
    }
  }

  Future<void> _pumpQueue() async {
    if (_pumping || !mounted) return;
    _pumping = true;
    try {
      while (mounted) {
        final award = _awards?.current;
        if (award == null) {
          if (_playing != null) {
            setState(() {
              _playing = null;
              _from = null;
              _to = null;
              _dragDy = 0;
            });
          }
          break;
        }
        await _play(award);
        if (!mounted) break;
        _awards?.onDismissed();
      }
    } finally {
      _pumping = false;
    }
  }

  void _requestDismiss() {
    if (_dismissRequested) return;
    _dismissRequested = true;
  }

  Future<void> _waitHoldOrDismiss() async {
    final end = DateTime.now().add(_holdDuration);
    while (mounted && !_dismissRequested && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _waitUntilDismissed() async {
    while (mounted && !_dismissRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _play(XpAward award) async {
    _entrance?.dispose();
    _magic?.dispose();
    _exit?.dispose();
    _entrance = null;
    _magic = null;
    _exit = null;
    _dismissRequested = false;
    _skipMagic = false;

    setState(() {
      _playing = award;
      _from = null;
      _to = null;
      _dragDy = 0;
      _seed = award.skillId.hashCode ^ award.amount;
    });

    final entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _entrance = entrance;
    entrance.addListener(_tick);
    await entrance.forward();
    if (!mounted) return;

    await _waitHoldOrDismiss();
    if (!mounted) return;

    if (!_dismissRequested && !_skipMagic && _hudVisible) {
      _captureEndpoints();
      final magic = AnimationController(
        vsync: this,
        duration: _magicDuration,
      );
      _magic = magic;
      magic.addListener(_tick);
      await Future.any([
        magic.forward(),
        _waitUntilDismissed(),
      ]);
      if (!mounted) return;
      if (magic.isAnimating) magic.stop();
    } else if (_skipMagic && !_dismissRequested) {
      // Tap opened the skill sheet; linger until the delayed dismiss fires.
      await _waitUntilDismissed();
      if (!mounted) return;
    }

    // Drop magic paint before exit so it doesn't linger under the sheet.
    if (_magic != null) {
      _magic!.dispose();
      _magic = null;
      _from = null;
      _to = null;
    }

    final exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _exit = exit;
    exit.addListener(_tick);
    await exit.forward();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _openSkillDrawer(XpAward award) {
    // Overlay lives above the Navigator in [MaterialApp.builder]; use the
    // root navigator context so the sheet has a valid route host.
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
    // Linger so the badge doesn't vanish the instant the sheet opens.
    _skipMagic = true;
    Future<void>.delayed(_tapDismissDelay, () {
      if (mounted) _requestDismiss();
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    // Only track upward drags.
    final next = (_dragDy + details.delta.dy).clamp(-120.0, 0.0);
    if (next == _dragDy) return;
    setState(() => _dragDy = next);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDy <= -_dismissDragThreshold || velocity <= _dismissVelocity) {
      _requestDismiss();
      return;
    }
    setState(() => _dragDy = 0);
  }

  void _captureEndpoints() {
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;

    final badgeBox =
        _badgeKey.currentContext?.findRenderObject() as RenderBox?;
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
      _from = from;
      _to = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_playing == null) return const SizedBox.shrink();

    final topPad = MediaQuery.paddingOf(context).top;
    final top = _hudVisible
        ? topPad + MapChromeInsets.topRowHeight + 4
        : topPad + 8;

    final entrance = _entrance;
    final magic = _magic;
    final exit = _exit;

    final enterT = Curves.easeOutBack.transform(entrance?.value ?? 1.0);
    final exitT = Curves.easeInCubic.transform(exit?.value ?? 0.0);
    final opacity = ((entrance?.value ?? 1.0) * (1.0 - exitT)).clamp(0.0, 1.0);
    final scale = (0.88 + 0.12 * enterT) * (1.0 - 0.06 * exitT);
    final slideY =
        (1.0 - enterT) * -18.0 + exitT * -28.0 + _dragDy;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_hudVisible &&
              magic != null &&
              _from != null &&
              _to != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: XpMagicStringPainter(
                    from: _from!,
                    to: _to!,
                    progress: Curves.easeInOutCubic.transform(magic.value),
                    seed: _seed,
                  ),
                ),
              ),
            ),
          Positioned(
            top: top,
            left: _hudVisible ? 12 : 0,
            right: _hudVisible ? null : 0,
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(0, slideY),
                child: Transform.scale(
                  alignment: _hudVisible
                      ? Alignment.topLeft
                      : Alignment.topCenter,
                  scale: scale,
                  child: Align(
                    alignment: _hudVisible
                        ? Alignment.centerLeft
                        : Alignment.topCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openSkillDrawer(_playing!),
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      child: KeyedSubtree(
                        key: _badgeKey,
                        child: XpAwardBadge(award: _playing!),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
