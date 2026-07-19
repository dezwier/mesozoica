import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_notification.dart';
import '../services/api_response_cache.dart';
import '../services/notification_service.dart';

/// Server-backed user notifications (friend requests).
///
/// Stale-while-revalidate: [hydrate] loads from disk; [refreshInBackground]
/// syncs from API. Opening the bell does not block on network.
class NotificationController extends ChangeNotifier {
  NotificationController({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

  static const String _cacheName = 'notifications_v1';
  static const Duration _cacheTtl = Duration(days: 365);

  final NotificationService _notificationService;
  final List<UserNotificationItem> _items = [];
  int? _activeUserId;
  bool _isLoading = false;
  bool _isRefreshingInBackground = false;
  Future<void>? _inFlightRefresh;
  bool _refreshQueued = false;
  final Set<int> _seenForBadgeIds = {};

  List<UserNotificationItem> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((item) => !item.read).length;
  bool get isLoading => _isLoading;
  bool get isRefreshingInBackground => _isRefreshingInBackground;

  int get unreadCountForBadge => _items
      .where((item) => !item.read && !_seenForBadgeIds.contains(item.id))
      .length;

  Future<void> hydrate(int? userId) async {
    if (userId == null) return;
    if (_activeUserId != userId) {
      _items.clear();
      _seenForBadgeIds.clear();
      _activeUserId = userId;
    }
    try {
      final raw = await ApiResponseCache.instance.get(
        _cacheName,
        userId,
        ttl: _cacheTtl,
      );
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final list = decoded['notifications'] as List<dynamic>? ?? [];
      _items
        ..clear()
        ..addAll(
          list
              .map(
                (entry) =>
                    UserNotificationItem.fromJson(entry as Map<String, dynamic>),
              )
              .where(
                (item) =>
                    item.isFriendRequestRelated || item.isSiteDiscovered,
              ),
        );
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('NotificationController.hydrate failed: $error\n$stackTrace');
    }
  }

  void markCurrentAsSeenForBadge() {
    var changed = false;
    for (final item in _items) {
      if (_seenForBadgeIds.add(item.id)) changed = true;
    }
    if (changed) notifyListeners();
  }

  void _bindAuthenticatedUser(int? authenticatedUserId) {
    if (authenticatedUserId == null) return;
    if (_activeUserId != null && _activeUserId != authenticatedUserId) {
      _items.clear();
      _seenForBadgeIds.clear();
    }
    _activeUserId = authenticatedUserId;
  }

  Future<void> refreshInBackground({int? authenticatedUserId}) {
    _bindAuthenticatedUser(authenticatedUserId);
    if (_inFlightRefresh != null) {
      _refreshQueued = true;
      return _inFlightRefresh!;
    }
    _isRefreshingInBackground = true;
    notifyListeners();
    _inFlightRefresh = _fetchAndApply().whenComplete(() {
      _inFlightRefresh = null;
      _isRefreshingInBackground = false;
      notifyListeners();
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(
          refreshInBackground(authenticatedUserId: _activeUserId),
        );
      }
    });
    return _inFlightRefresh!;
  }

  Future<void> refreshAndWait({int? authenticatedUserId}) async {
    _bindAuthenticatedUser(authenticatedUserId);
    _isLoading = true;
    notifyListeners();
    try {
      await refreshInBackground(authenticatedUserId: authenticatedUserId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchAndApply() async {
    try {
      final result = await _notificationService.getNotifications();
      _items
        ..clear()
        ..addAll(
          result.items.where(
            (item) => item.isFriendRequestRelated || item.isSiteDiscovered,
          ),
        );
      await _persistItems();
    } catch (error, stackTrace) {
      debugPrint('NotificationController._fetchAndApply: $error\n$stackTrace');
    }
  }

  Future<void> _persistItems() async {
    final userId = _activeUserId;
    if (userId == null) return;
    try {
      await ApiResponseCache.instance.set(
        _cacheName,
        userId,
        {
          'notifications': _items.map((item) => item.toJson()).toList(),
        },
      );
    } catch (error, stackTrace) {
      debugPrint('NotificationController._persistItems: $error\n$stackTrace');
    }
  }

  void clear() {
    _items.clear();
    _seenForBadgeIds.clear();
    _activeUserId = null;
    _inFlightRefresh = null;
    _refreshQueued = false;
    _isLoading = false;
    _isRefreshingInBackground = false;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    final unreadIds =
        _items.where((item) => !item.read && item.id > 0).map((item) => item.id);
    for (final id in unreadIds) {
      await markRead(id);
    }
  }

  Future<void> markRead(int id) async {
    if (id <= 0) return;
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final previous = _items[index];
    if (previous.read) return;

    _items[index] = previous.copyWith(read: true);
    notifyListeners();
    await _persistItems();

    final ok = await _notificationService.markRead(id);
    if (!ok) {
      _items[index] = previous;
      notifyListeners();
      await _persistItems();
    }
  }
}
