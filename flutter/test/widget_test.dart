import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesozoica/controllers/auth_controller.dart';
import 'package:mesozoica/models/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Profile parses API payload', () {
    final profile = Profile.fromJson({
      'id': 1,
      'username': 'rex',
      'display_name': 'Dr. Rex',
      'email': 'rex@example.com',
      'specialization': 'Paleontologist',
      'level': 2,
      'achievements': ['First dig'],
      'actual_dinosaurs_count': 3,
    });

    expect(profile.username, 'rex');
    expect(profile.displayName, 'Dr. Rex');
    expect(profile.actualDinosaursCount, 3);
    expect(profile.achievements, ['First dig']);
  });

  test('AuthController starts logged out after initialize', () async {
    final authController = AuthController();
    await authController.initialize();

    expect(authController.isInitializing, isFalse);
    expect(authController.isLoggedIn, isFalse);
    expect(authController.currentUser, isNull);
  });
}
