import 'dart:async';

import 'package:flutter/services.dart';

/// Stronger discovery feedback than a single [HapticFeedback.heavyImpact].
Future<void> playDiscoveryHaptic() async {
  await HapticFeedback.heavyImpact();
  await Future<void>.delayed(const Duration(milliseconds: 90));
  await HapticFeedback.vibrate();
  await Future<void>.delayed(const Duration(milliseconds: 120));
  await HapticFeedback.heavyImpact();
}

void playDiscoveryHapticFireAndForget() {
  unawaited(playDiscoveryHaptic());
}
