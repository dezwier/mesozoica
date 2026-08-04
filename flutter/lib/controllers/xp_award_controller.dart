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

  /// Copy with a new [id] (and optionally merged [amount]).
  XpAward copyWith({int? id, int? amount}) {
    return XpAward(
      id: id ?? this.id,
      skillId: skillId,
      skillName: skillName,
      sourceLabel: sourceLabel,
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
/// See [xp_source_labels.dart] for the source-key split.
class XpAwardController extends ChangeNotifier {
  final List<XpAward> _active = [];
  final List<XpAward> _celebrationStash = [];
  bool _hudVisible = true;
  int _nextId = 1;

  /// Floating-badge awards currently on-screen (oldest first).
  List<XpAward> get activeAwards => List.unmodifiable(_active);

  /// Celebration-bound awards not yet claimed by a plaque (oldest first).
  @visibleForTesting
  List<XpAward> get celebrationStash => List.unmodifiable(_celebrationStash);

  /// Whether the map profile HUD is on-screen (magic-string target).
  bool get hudVisible => _hudVisible;

  bool get hasPending => _active.isNotEmpty;

  void setHudVisible(bool visible) {
    if (_hudVisible == visible) return;
    _hudVisible = visible;
    notifyListeners();
  }

  void enqueue(XpAward award) {
    enqueueAll([award]);
  }

  /// Enqueue **badge-only** awards (celebration sources are ignored).
  void enqueueAll(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (award.amount <= 0) continue;
      if (isCelebrationXpSource(award.sourceKey)) continue;
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

  /// Remove and return stashed awards whose [sourceKey] is in [keys].
  ///
  /// Celebrations call this when opening so the plaque embeds every XP line
  /// for that event. When [mergeSameKey] is true, multiple awards with the
  /// same source key (e.g. two identification quiz steps) become one row.
  List<XpAward> claimCelebrationAwards(
    Set<String> keys, {
    bool mergeSameKey = false,
  }) {
    if (keys.isEmpty || _celebrationStash.isEmpty) return const [];

    final claimed = <XpAward>[];
    final remaining = <XpAward>[];
    for (final award in _celebrationStash) {
      if (keys.contains(award.sourceKey)) {
        claimed.add(award);
      } else {
        remaining.add(award);
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
    final had = _active.isNotEmpty || _celebrationStash.isNotEmpty;
    _active.clear();
    _celebrationStash.clear();
    if (had) notifyListeners();
  }
}
