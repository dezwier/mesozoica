import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesozoica/widgets/profile/auth_view.dart';

void main() {
  testWidgets('does not expose an embedded test-account autofill action', (
    tester,
  ) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    addTearDown(usernameController.dispose);
    addTearDown(passwordController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthView(
            usernameController: usernameController,
            passwordController: passwordController,
            isLoading: false,
            onLogin: () {},
          ),
        ),
      ),
    );

    expect(find.text('Fill test account'), findsNothing);

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Fill test account'), findsNothing);
  });
}
