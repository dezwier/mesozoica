import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/user_notification.dart';
import '../services/api_response_cache.dart';
import '../services/app_badge_service.dart';
import '../services/notification_service.dart';

/// Server-backed user notifications (friend requests).
///
/// Stale-while-revalidate: [hydrate] loads from disk; [refreshInBackground]
/// syncs from API. Opening the bell does not block on network.
class NotificationController extends ChangeNotifier {
  NotificationController({
    NotificationService? notificationService,
    ResponseCache? responseCache,
    Future<void> Function(int count)? setAppBadgeCount,
  }) : _notificationService = notificationService ?? NotificationService(),
       _responseCache = responseCache ?? ApiResponseCache.instance,
       _setAppBadgeCount = setAppBadgeCount ?? AppBadgeService.setBadgeCount;

  static const String _cacheKey = 'notifications_v1';
  static const Duration _cacheTtl = Duration(days: 365);

  final NotificationService _notificationService;
  final ResponseCache _responseCache;
  final Future<void> Function(int count) _setAppBadgeCount;
  final List<UserNotificationItem> _items = [];
  int? _activeUserId;
  bool _isLoading = false;
  bool _isRefreshingInBackground = false;
  Future<void>? _inFlightRefresh;
  bool _refreshQueued = false;
  final Set<int> _seenForBadgeIds = {};
  final Set<int> _pendingMarkReadIds = {};

  List<UserNotificationItem> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((item) => !item.read).length;
  bool get isLoading => _isLoading;
  bool get isRefreshingInBackground => _isRefreshingInBackground;

  /// In-app bell badge: unread items not yet opened in the overlay.
  int get unreadCountForBadge => _items
      .where((item) => !item.read && !_seenForBadgeIds.contains(item.id))
      .length;

  void _syncAppBadge() {
    unawaited(_setAppBadgeCount(unreadCount));
  }

  Future<void> hydrate(int? userId) async {
    if (userId == null) return;
    if (_activeUserId != userId) {
      _items.clear();
      _seenForBadgeIds.clear();
      _activeUserId = userId;
    }
    try {
      final raw = await _responseCache.get(_cacheKey, userId, ttl: _cacheTtl);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final list = decoded['notifications'] as List<dynamic>? ?? [];
      final pendingRead = decoded['pending_mark_read_ids'];
      _pendingMarkReadIds
        ..clear()
        ..addAll(
          pendingRead is List
              ? pendingRead.whereType<num>().map((id) => id.toInt())
              : const <int>[],
        );
      _items
        ..clear()
        ..addAll(
          list
              .map(
                (entry) => UserNotificationItem.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .where((item) => item.isInAppBellItem),
        );
      notifyListeners();
      _syncAppBadge();
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
        unawaited(refreshInBackground(authenticatedUserId: _activeUserId));
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
        ..addAll(result.items.where((item) => item.isInAppBellItem));
      await _persistItems();
      _syncAppBadge();
      for (final id in _pendingMarkReadIds.toList()) {
        unawaited(markRead(id));
      }
    } catch (error, stackTrace) {
      debugPrint('NotificationController._fetchAndApply: $error\n$stackTrace');
    }
  }

  Future<void> _persistItems() async {
    final userId = _activeUserId;
    if (userId == null) return;
    try {
      await _responseCache.set(_cacheKey, userId, {
        'notifications': _items.map((item) => item.toJson()).toList(),
        'pending_mark_read_ids': _pendingMarkReadIds.toList(),
      });
    } catch (error, stackTrace) {
      debugPrint('NotificationController._persistItems: $error\n$stackTrace');
    }
  }

  void clear() {
    _items.clear();
    _seenForBadgeIds.clear();
    _pendingMarkReadIds.clear();
    _activeUserId = null;
    _inFlightRefresh = null;
    _refreshQueued = false;
    _isLoading = false;
    _isRefreshingInBackground = false;
    notifyListeners();
    _syncAppBadge();
  }

  Future<void> markAllRead() async {
    final unreadIds = _items
        .where((item) => !item.read && item.id > 0)
        .map((item) => item.id);
    for (final id in unreadIds) {
      await markRead(id);
    }
  }

  Future<void> markRead(int id) async {
    if (id <= 0) return;
    _pendingMarkReadIds.add(id);
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) {
      await _persistItems();
      final ok = await _notificationService.markRead(id);
      if (ok) {
        _pendingMarkReadIds.remove(id);
        await _persistItems();
      }
      return;
    }
    final previous = _items[index];
    if (previous.read) {
      _pendingMarkReadIds.remove(id);
      await _persistItems();
      return;
    }

    _items[index] = previous.copyWith(read: true);
    notifyListeners();
    _syncAppBadge();
    await _persistItems();

    final ok = await _notificationService.markRead(id);
    if (ok) {
      _pendingMarkReadIds.remove(id);
      await _persistItems();
    } else {
      _items[index] = previous;
      notifyListeners();
      _syncAppBadge();
      await _persistItems();
    }
  }
}
