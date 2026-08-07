import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesozoica/controllers/notification_controller.dart';
import 'package:mesozoica/features/notifications/domain/celebration_event.dart';
import 'package:mesozoica/features/notifications/presentation/celebration_controller.dart';
import 'package:mesozoica/features/notifications/presentation/celebration_host.dart';
import 'package:mesozoica/services/api_response_cache.dart';
import 'package:mesozoica/services/notification_service.dart';
import 'package:mesozoica/widgets/cards/card_detail_sheet.dart';

class _NotificationService extends NotificationService {
  final List<int> marked = [];

  @override
  Future<bool> markRead(int notificationId) async {
    marked.add(notificationId);
    return true;
  }
}

class _MemoryCache implements ResponseCache {
  @override
  Future<void> clearForUser(int? userId) async {}

  @override
  Future<String?> get(
    String name,
    int? userId, {
    Duration ttl = const Duration(hours: 24),
  }) async => null;

  @override
  Future<void> set(String name, int? userId, Object payload) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('host is topmost and applies show-time side effects once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'celebration_presented_v1_7': 0});
    final celebrations = CelebrationController();
    await celebrations.bindUser(7, const []);
    final service = _NotificationService();
    final notifications = NotificationController(
      notificationService: service,
      responseCache: _MemoryCache(),
      setAppBadgeCount: (_) async {},
    );
    var underlyingTaps = 0;
    var haptics = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: celebrations),
          ChangeNotifierProvider.value(value: notifications),
        ],
        child: MaterialApp(
          builder: (context, child) => CelebrationHost(
            playHaptic: () => haptics++,
            eventBuilder: (_, event) => Text('Celebration ${event.siteId}'),
            child: child!,
          ),
          home: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => underlyingTaps++,
            child: const Scaffold(body: Center(child: Text('Underneath'))),
          ),
        ),
      ),
    );

    celebrations.enqueue(
      const CelebrationEvent(
        kind: CelebrationKind.siteDiscovered,
        siteId: 42,
        notificationId: 8,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Celebration 42'), findsOneWidget);
    expect(haptics, 1);
    expect(service.marked, [8]);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(underlyingTaps, 0);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(celebrations.current, isNull);
  });

  testWidgets('targeted card dismissal leaves unrelated card route open', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    CardDetailSheet.show<void>(
      pageContext,
      identity: const CardDetailIdentity.site(1),
      builder: (_) => const Text('Site one'),
    );
    await tester.pumpAndSettle();
    CardDetailSheet.show<void>(
      pageContext,
      identity: const CardDetailIdentity.site(2),
      builder: (_) => const Text('Site two'),
    );
    await tester.pumpAndSettle();

    CardDetailSheet.dismissMatching(const CardDetailIdentity.site(1));
    await tester.pumpAndSettle();

    expect(find.text('Site one'), findsNothing);
    expect(find.text('Site two'), findsOneWidget);
    CardDetailSheet.dismissMatching(const CardDetailIdentity.site(2));
    await tester.pumpAndSettle();
  });
}
