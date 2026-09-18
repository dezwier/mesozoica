import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/controllers/theme_controller.dart';
import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/services/location_service.dart';
import 'package:mesozoica/widgets/profile/auth_view.dart';
import 'package:mesozoica/widgets/profile/settings_account_tab.dart';
import 'package:mesozoica/widgets/profile/settings_app_tab.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('auth screen uses official Sign in with Apple label', (
    tester,
  ) async {
    final username = TextEditingController();
    final password = TextEditingController();
    addTearDown(username.dispose);
    addTearDown(password.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: AuthView(
              usernameController: username,
              passwordController: password,
              isLoading: false,
              onLogin: () {},
              onSignInWithGoogle: ({bool loginOnly = false}) async {},
              onSignInWithApple: ({bool loginOnly = false}) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Apple'), findsNothing);
  });

  testWidgets(
    'App settings tab exposes background location and delete account',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController()),
            ChangeNotifierProvider(create: (_) => LocationService()),
          ],
          child: MaterialApp(
            home: Scaffold(body: SettingsAppTab(onRequestDeleteAccount: () {})),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Background location'), findsOneWidget);
      expect(find.text('Explore in background'), findsNothing);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Account deletion policy'), findsOneWidget);
    },
  );

  testWidgets('Account tab hides password fields for Apple-only accounts', (
    tester,
  ) async {
    final email = TextEditingController(text: 'hidden@example.com');
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    addTearDown(email.dispose);
    addTearDown(currentPassword.dispose);
    addTearDown(newPassword.dispose);
    addTearDown(confirmPassword.dispose);

    final profile = Profile.fromJson({
      'id': 1,
      'username': 'rex',
      'email': 'hidden@example.com',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsAccountTab(
            currentUser: profile,
            scrollController: null,
            emailController: email,
            currentPasswordController: currentPassword,
            newPasswordController: newPassword,
            confirmPasswordController: confirmPassword,
            emailValidator: (_) => null,
            newPasswordValidator: (_) => null,
            confirmPasswordValidator: (_) => null,
            linkedAccountRows: const [],
            isLoadingLinked: false,
            showPasswordFields: false,
            onRequestDeleteAccount: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Email and password'), findsNothing);
    expect(find.text('Current password'), findsNothing);
    expect(find.text('Sign-in methods'), findsOneWidget);
    expect(find.text('Delete data'), findsOneWidget);
  });
}
