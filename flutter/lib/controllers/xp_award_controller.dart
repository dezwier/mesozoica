import 'package:flutter/foundation.dart';

/// One skill XP gain to present as a global badge.
///
/// Any backend action that awards skill XP must return an updated profile that
/// the client applies via [AuthController.applyUser] (or
/// `refreshProfile(announceXp: true)`). The global badge is driven only from
/// positive skill XP deltas.
class XpAward {
  const XpAward({
    required this.skillId,
    required this.skillName,
    required this.amount,
  });

  final String skillId;
  final String skillName;
  final int amount;
}

/// Sequential queue of XP-earned badges for the global overlay.
class XpAwardController extends ChangeNotifier {
  final List<XpAward> _queue = [];
  XpAward? _current;
  bool _hudVisible = true;

  /// Award currently being shown, if any.
  XpAward? get current => _current;

  /// Whether the map profile HUD is on-screen (magic-string target).
  bool get hudVisible => _hudVisible;

  bool get hasPending => _current != null || _queue.isNotEmpty;

  void setHudVisible(bool visible) {
    if (_hudVisible == visible) return;
    _hudVisible = visible;
    notifyListeners();
  }

  void enqueue(XpAward award) {
    if (award.amount <= 0) return;
    _queue.add(award);
    _promoteIfIdle();
  }

  void enqueueAll(Iterable<XpAward> awards) {
    var added = false;
    for (final award in awards) {
      if (award.amount <= 0) continue;
      _queue.add(award);
      added = true;
    }
    if (added) _promoteIfIdle();
  }

  /// Called by the overlay when the current badge animation finishes.
  void onDismissed() {
    if (_current == null) return;
    _current = null;
    _promoteIfIdle();
    if (_current == null) notifyListeners();
  }

  void clear() {
    _queue.clear();
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  void _promoteIfIdle() {
    if (_current != null || _queue.isEmpty) return;
    _current = _queue.removeAt(0);
    notifyListeners();
  }
}
