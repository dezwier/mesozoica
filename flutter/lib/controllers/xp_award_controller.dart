import 'package:flutter/foundation.dart';

/// One skill XP gain to present as a global badge.
///
/// Any backend action that awards skill XP must return an updated profile that
/// the client applies via [AuthController.applyUser] (or
/// `refreshProfile(announceXp: true)`). Badges are driven from positive
/// skill_breakdown (XP source) deltas when available.
class XpAward {
  const XpAward({
    required this.id,
    required this.skillId,
    required this.skillName,
    required this.sourceLabel,
    required this.amount,
  });

  /// Stable id for overlay lifecycle / dismiss.
  final int id;

  final String skillId;

  /// Skill display name (skill sheet / fallback).
  final String skillName;

  /// XP source / parameter label shown on the badge.
  final String sourceLabel;

  final int amount;
}

/// Concurrent stack of XP-earned badges for the global overlay.
class XpAwardController extends ChangeNotifier {
  final List<XpAward> _active = [];
  bool _hudVisible = true;
  int _nextId = 1;

  /// Awards currently on-screen (oldest first — stack top to bottom).
  List<XpAward> get activeAwards => List.unmodifiable(_active);

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

  void enqueueAll(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (award.amount <= 0) continue;
      _active.add(
        XpAward(
          id: _nextId++,
          skillId: award.skillId,
          skillName: award.skillName,
          sourceLabel: award.sourceLabel,
          amount: award.amount,
        ),
      );
      added = true;
    }
    if (added) notifyListeners();
  }

  /// Called by the overlay when a badge finishes its exit animation.
  void dismiss(int id) {
    final before = _active.length;
    _active.removeWhere((award) => award.id == id);
    if (_active.length != before) notifyListeners();
  }

  void clear() {
    if (_active.isEmpty) return;
    _active.clear();
    notifyListeners();
  }
}
