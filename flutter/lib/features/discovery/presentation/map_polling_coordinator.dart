import 'dart:async';

/// Timer and burst-backoff mechanics for field-site polling.
class MapPollingCoordinator {
  static const burstDelays = [
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 25),
    Duration(seconds: 40),
    Duration(seconds: 60),
    Duration(seconds: 90),
    Duration(seconds: 120),
  ];

  Timer? _periodic;
  int _burstGeneration = 0;

  void startPeriodic({
    required Duration interval,
    required bool Function() isValid,
    required Future<void> Function() poll,
  }) {
    stopPeriodic();
    _periodic = Timer.periodic(interval, (_) {
      if (isValid()) unawaited(poll());
    });
  }

  void scheduleBurst({
    required bool Function() isValid,
    required Future<void> Function() poll,
  }) {
    final generation = ++_burstGeneration;
    void run() {
      if (generation == _burstGeneration && isValid()) unawaited(poll());
    }

    run();
    for (final delay in burstDelays) {
      Future<void>.delayed(delay, run);
    }
  }

  void stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  void stopBurst() => _burstGeneration++;

  void dispose() {
    stopPeriodic();
    stopBurst();
  }
}
