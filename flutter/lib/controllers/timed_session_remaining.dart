import 'package:flutter/foundation.dart';

import '../models/tool_session.dart';

/// Syncs a timed-tool countdown notifier; returns true when the session expired.
///
/// Call [onExpired] once when remaining hits zero so HUDs can dismiss.
bool syncTimedSessionRemaining({
  required ToolSession? session,
  required ValueNotifier<Duration?> remainingListenable,
  required VoidCallback onExpired,
}) {
  final expires = session?.expiresAt;
  if (session == null || expires == null) {
    if (remainingListenable.value != null) {
      remainingListenable.value = null;
    }
    return false;
  }

  final left = expires.difference(DateTime.now().toUtc());
  if (left.isNegative || left == Duration.zero) {
    if (remainingListenable.value != Duration.zero) {
      remainingListenable.value = Duration.zero;
    }
    onExpired();
    return true;
  }

  final prev = remainingListenable.value;
  // Second precision so HUDs can dismiss the moment the clock hits zero.
  if (prev == null || prev.inSeconds != left.inSeconds) {
    remainingListenable.value = left;
  }
  return false;
}
