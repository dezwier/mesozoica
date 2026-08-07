import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/user_notification.dart';
import '../domain/celebration_event.dart';

class CelebrationController extends ChangeNotifier {
  static const _progressKeyPrefix = 'celebration_presented_v1_';

  final List<_QueuedCelebration> _queue = [];
  final Set<String> _knownKeys = {};
  int? _activeUserId;
  int _lastPresentedNotificationId = 0;
  bool _foreground = true;
  bool _progressLoaded = false;

  CelebrationEvent? get current =>
      _foreground && _queue.isNotEmpty ? _queue.first.event : null;
  int get pendingCount => _queue.length;

  Future<void> bindUser(int? userId, List<UserNotificationItem> items) async {
    if (_activeUserId == userId && _progressLoaded) return;
    for (final queued in _queue) {
      if (!queued.completer.isCompleted) queued.completer.complete();
    }
    _queue.clear();
    _knownKeys.clear();
    _activeUserId = userId;
    _lastPresentedNotificationId = 0;
    _progressLoaded = false;
    if (userId == null) {
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = '$_progressKeyPrefix$userId';
    final saved = prefs.getInt(key);
    if (saved == null) {
      final historical = items
          .where((item) => item.isCelebration && item.id > 0)
          .map((item) => item.id);
      _lastPresentedNotificationId = historical.isEmpty
          ? 0
          : historical.reduce((a, b) => a > b ? a : b);
      await prefs.setInt(key, _lastPresentedNotificationId);
    } else {
      _lastPresentedNotificationId = saved;
    }
    _progressLoaded = true;
    notifyListeners();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    notifyListeners();
  }

  Future<void> enqueue(CelebrationEvent event) {
    for (final queued in _queue) {
      if (queued.event.dedupeKey == event.dedupeKey ||
          queued.event.fallbackKey == event.fallbackKey) {
        return queued.completer.future;
      }
    }
    if (_knownKeys.contains(event.dedupeKey) ||
        _knownKeys.contains(event.fallbackKey)) {
      return Future<void>.value();
    }
    final queued = _QueuedCelebration(event);
    _queue.add(queued);
    _knownKeys.add(event.dedupeKey);
    _knownKeys.add(event.fallbackKey);
    notifyListeners();
    return queued.completer.future;
  }

  void reconcileUnread(Iterable<UserNotificationItem> items) {
    if (!_progressLoaded) return;
    final pending =
        items
            .where(
              (item) =>
                  item.isCelebration &&
                  !item.read &&
                  item.siteId != null &&
                  item.id > _lastPresentedNotificationId,
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    for (final item in pending) {
      unawaited(enqueue(CelebrationEvent.fromNotification(item)));
    }
  }

  Future<void> markCurrentVisible() async {
    final id = current?.notificationId;
    final userId = _activeUserId;
    if (id == null || id <= _lastPresentedNotificationId || userId == null) {
      return;
    }
    _lastPresentedNotificationId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_progressKeyPrefix$userId', id);
  }

  void dismissCurrent() {
    if (_queue.isEmpty) return;
    final queued = _queue.removeAt(0);
    _knownKeys.remove(queued.event.fallbackKey);
    queued.completer.complete();
    notifyListeners();
  }

  void clear() {
    for (final queued in _queue) {
      if (!queued.completer.isCompleted) queued.completer.complete();
    }
    _queue.clear();
    _knownKeys.clear();
    _activeUserId = null;
    _progressLoaded = false;
    _lastPresentedNotificationId = 0;
    notifyListeners();
  }
}

class _QueuedCelebration {
  _QueuedCelebration(this.event);
  final CelebrationEvent event;
  final Completer<void> completer = Completer<void>();
}
