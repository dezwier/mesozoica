import 'package:flutter/foundation.dart';

import '../utils/xp_source_labels.dart';

/// One skill XP gain to present to the player.
///
/// Presentation is exclusive: either embedded in a celebration plaque (big
/// events) or shown as a floating XP badge (small events). See
/// [xp_source_labels.dart] library doc and [XpAwardController.announceAwards].
///
/// Any backend action that awards skill XP must return an updated profile that
/// the client applies via [AuthController.applyUser] (or
/// `refreshProfile(announceXp: true)`). Awards are driven from positive
/// skill_breakdown (XP source) deltas when available.
class XpAward {
  const XpAward({
    required this.id,
    required this.skillId,
    required this.skillName,
    required this.sourceLabel,
    required this.amount,
    this.sourceKey = '',
  });

  /// Stable id for overlay lifecycle / dismiss.
  final int id;

  final String skillId;

  /// Skill display name (skill sheet / fallback).
  final String skillName;

  /// XP source / parameter label shown on the badge or plaque row.
  final String sourceLabel;

  final int amount;

  /// skill_breakdown key (empty for remainder / skill-name fallback → badge).
  final String sourceKey;

  /// Copy with a new [id] (and optionally merged [amount] / [sourceLabel]).
  XpAward copyWith({int? id, int? amount, String? sourceLabel}) {
    return XpAward(
      id: id ?? this.id,
      skillId: skillId,
      skillName: skillName,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      amount: amount ?? this.amount,
      sourceKey: sourceKey,
    );
  }
}

/// Routes announced XP to exactly one presentation path:
///
/// - **Celebration stash** — big events ([isCelebrationXpSource]); claimed by
///   the matching celebration so all XP for that event appears in the plaque.
/// - **Floating badge overlay** — small events (distance, disguise, exploration).
///
/// While the app is backgrounded, every floating-badge source is held and
/// flushed as one badge per source on resume (summed amount; distance labels
/// refresh from the total). Celebrations are never merged — each plaque claims
/// one event via [claimCelebrationAwards] (`oneEvent: true`).
///
/// See [xp_source_labels.dart] for the source-key split.
class XpAwardController extends ChangeNotifier {
  final List<XpAward> _active = [];
  final List<XpAward> _celebrationStash = [];
  /// Bundlable badge awards accrued while backgrounded, keyed by sourceKey.
  final Map<String, XpAward> _backgroundBundle = {};
  bool _hudVisible = true;
  bool _appForeground = true;
  int _nextId = 1;

  /// Floating-badge awards currently on-screen (oldest first).
  List<XpAward> get activeAwards => List.unmodifiable(_active);

  /// Celebration-bound awards not yet claimed by a plaque (oldest first).
  @visibleForTesting
  List<XpAward> get celebrationStash => List.unmodifiable(_celebrationStash);

  /// Held bundlable awards waiting for resume (oldest sourceKey first).
  @visibleForTesting
  List<XpAward> get backgroundBundle =>
      List.unmodifiable(_backgroundBundle.values);

  /// Whether the map profile HUD is on-screen (magic-string target).
  bool get hudVisible => _hudVisible;

  bool get hasPending => _active.isNotEmpty || _backgroundBundle.isNotEmpty;

  void setHudVisible(bool visible) {
    if (_hudVisible == visible) return;
    _hudVisible = visible;
    notifyListeners();
  }

  /// Track app foreground so bundlable XP can accumulate while away.
  ///
  /// On resume, flushes [_backgroundBundle] into floating badges (one per
  /// source, summed amounts).
  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (foreground) {
      _flushBackgroundBundle();
    }
  }

  void enqueue(XpAward award) {
    enqueueAll([award]);
  }

  /// Enqueue **badge-only** awards (celebration sources are ignored).
  ///
  /// While backgrounded, all badge awards are held and merged by [sourceKey]
  /// until [setAppForeground] (true).
  void enqueueAll(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (award.amount <= 0) continue;
      if (isCelebrationXpSource(award.sourceKey)) continue;
      if (!_appForeground && isBackgroundBundleXpSource(award.sourceKey)) {
        _accumulateBackground(award);
        continue;
      }
      _active.add(award.copyWith(id: _nextId++));
      added = true;
    }
    if (added) notifyListeners();
  }

  void _accumulateBackground(XpAward award) {
    final key = award.sourceKey;
    final existing = _backgroundBundle[key];
    if (existing == null) {
      _backgroundBundle[key] = award.copyWith(id: 0);
    } else {
      final mergedAmount = existing.amount + award.amount;
      _backgroundBundle[key] = existing.copyWith(
        amount: mergedAmount,
        sourceLabel: xpSourceLabelForAward(key, mergedAmount),
      );
    }
  }

  void _flushBackgroundBundle() {
    if (_backgroundBundle.isEmpty) return;
    final pending = List<XpAward>.from(_backgroundBundle.values);
    _backgroundBundle.clear();
    var added = false;
    for (final award in pending) {
      if (award.amount <= 0) continue;
      _active.add(award.copyWith(id: _nextId++));
      added = true;
    }
    if (added) notifyListeners();
  }

  /// Stash **celebration-bound** awards for a later [claimCelebrationAwards].
  void stashCelebrationAwards(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (award.amount <= 0) continue;
      if (!isCelebrationXpSource(award.sourceKey)) continue;
      _celebrationStash.add(award.copyWith(id: _nextId++));
      added = true;
    }
    if (added) notifyListeners();
  }

  /// Route each award to a celebration stash **or** a floating badge — not both.
  void announceAwards(Iterable<XpAward> awards) {
    final badge = <XpAward>[];
    final celebration = <XpAward>[];
    for (final award in awards) {
      if (award.amount <= 0) continue;
      if (isCelebrationXpSource(award.sourceKey)) {
        celebration.add(award);
      } else {
        badge.add(award);
      }
    }
    enqueueAll(badge);
    stashCelebrationAwards(celebration);
  }

  /// Like [announceAwards], but distance XP from a closed-app gap is merged into
  /// one badge. Pure passive/active gaps use "Explore {m} …"; mixed gaps use
  /// "Explored … since last visit".
  ///
  /// Shown when [exploredMeters] ≥ 10 (even if XP is 0). Smaller gaps fall
  /// through to normal announce (no visit chip).
  void announceAwardsAfterVisit({
    required Iterable<XpAward> awards,
    required double exploredMeters,
  }) {
    if (exploredMeters < 10) {
      announceAwards(awards);
      return;
    }

    final distance = <XpAward>[];
    final celebration = <XpAward>[];
    final otherBadge = <XpAward>[];
    for (final award in awards) {
      if (award.amount <= 0) continue;
      if (kDistanceXpSourceKeys.contains(award.sourceKey)) {
        distance.add(award);
      } else if (isCelebrationXpSource(award.sourceKey)) {
        celebration.add(award);
      } else {
        otherBadge.add(award);
      }
    }

    final xp = distance.fold<int>(0, (sum, a) => sum + a.amount);
    final template = distance.isNotEmpty
        ? distance.first
        : const XpAward(
            id: 0,
            skillId: 'field_survey',
            skillName: 'Field Survey',
            sourceLabel: '',
            amount: 0,
            sourceKey: 'explore_100m_passively',
          );

    // Prefer "Explore {m} passively/actively" when the gap is a single distance
    // source; mixed active+passive keeps the visit wording.
    final onlyPassive = distance.isNotEmpty &&
        distance.every((a) => a.sourceKey == 'explore_100m_passively');
    final onlyActive = distance.isNotEmpty &&
        distance.every((a) => a.sourceKey == 'explore_100m_actively');
    final visitLabel = onlyPassive || onlyActive
        ? exploreDistanceXpLabel(template.sourceKey, exploredMeters)
        : exploredSinceLastVisitLabel(exploredMeters);

    _enqueueVisitAware([
      ...otherBadge,
      XpAward(
        id: 0,
        skillId: template.skillId,
        skillName: template.skillName,
        sourceLabel: visitLabel,
        amount: xp,
        sourceKey: template.sourceKey,
      ),
    ]);
    stashCelebrationAwards(celebration);
  }

  void _enqueueVisitAware(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (isCelebrationXpSource(award.sourceKey)) continue;
      // Allow amount == 0 for the visit distance chip only.
      if (award.amount < 0) continue;
      if (award.amount == 0 &&
          !award.sourceLabel.startsWith('Explored ') &&
          !award.sourceLabel.startsWith('Explore ')) {
        continue;
      }
      _active.add(award.copyWith(id: _nextId++));
      added = true;
    }
    if (added) notifyListeners();
  }

  /// Remove and return stashed awards whose [sourceKey] is in [keys].
  ///
  /// Celebrations call this when opening so the plaque embeds XP for that
  /// event. When [oneEvent] is true (default for discovery/documentation), at
  /// most one award per key is claimed (oldest first) so two background
  /// discoveries each get their own plaque instead of one merged total.
  /// When [mergeSameKey] is true, multiple awards with the same source key
  /// (e.g. two identification quiz steps) become one row.
  List<XpAward> claimCelebrationAwards(
    Set<String> keys, {
    bool mergeSameKey = false,
    bool oneEvent = false,
  }) {
    if (keys.isEmpty || _celebrationStash.isEmpty) return const [];

    final claimed = <XpAward>[];
    final remaining = <XpAward>[];
    if (oneEvent) {
      final takenKeys = <String>{};
      for (final award in _celebrationStash) {
        if (keys.contains(award.sourceKey) &&
            !takenKeys.contains(award.sourceKey)) {
          claimed.add(award);
          takenKeys.add(award.sourceKey);
        } else {
          remaining.add(award);
        }
      }
    } else {
      for (final award in _celebrationStash) {
        if (keys.contains(award.sourceKey)) {
          claimed.add(award);
        } else {
          remaining.add(award);
        }
      }
    }
    if (claimed.isEmpty) return const [];

    _celebrationStash
      ..clear()
      ..addAll(remaining);
    notifyListeners();

    if (!mergeSameKey) return claimed;

    final byKey = <String, XpAward>{};
    for (final award in claimed) {
      final existing = byKey[award.sourceKey];
      if (existing == null) {
        byKey[award.sourceKey] = award;
      } else {
        byKey[award.sourceKey] = existing.copyWith(
          amount: existing.amount + award.amount,
        );
      }
    }
    // Preserve first-seen order of keys among claimed awards.
    final order = <String>[];
    for (final award in claimed) {
      if (!order.contains(award.sourceKey)) order.add(award.sourceKey);
    }
    return [for (final key in order) byKey[key]!];
  }

  /// Called by the overlay when a badge finishes its exit animation.
  void dismiss(int id) {
    final before = _active.length;
    _active.removeWhere((award) => award.id == id);
    if (_active.length != before) notifyListeners();
  }

  void clear() {
    final had = _active.isNotEmpty ||
        _celebrationStash.isNotEmpty ||
        _backgroundBundle.isNotEmpty;
    _active.clear();
    _celebrationStash.clear();
    _backgroundBundle.clear();
    if (had) notifyListeners();
  }
}
