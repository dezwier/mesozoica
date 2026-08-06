import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesozoica/services/api_client.dart';
import 'package:mesozoica/services/token_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenRefreshCallback? previousCallback;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth_token': 'stale-token'});
    previousCallback = ApiClient.instance.onUnauthorized;
  });

  tearDown(() {
    ApiClient.instance.onUnauthorized = previousCallback;
  });

  test('sendGet refreshes token and retries once on 401', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      final auth = request.headers['Authorization'];
      if (auth == 'Bearer stale-token') {
        return http.Response('{"detail":"Invalid or expired token"}', 401);
      }
      if (auth == 'Bearer fresh-token') {
        return http.Response('{"ok":true}', 200);
      }
      return http.Response('unexpected', 500);
    });

    ApiClient.instance.onUnauthorized = () async {
      await TokenStorage.saveToken('fresh-token');
      return true;
    };

    final response = await ApiClient.instance.sendGet(
      Uri.parse('https://example.test/api/v1/users/me'),
      client: client,
      headers: {'Authorization': 'Bearer stale-token'},
    );

    expect(response.statusCode, 200);
    expect(calls, 2);
    expect(await TokenStorage.loadToken(), 'fresh-token');
  });

  test('sendGet does not retry when refresh fails', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('{"detail":"Invalid or expired token"}', 401);
    });

    ApiClient.instance.onUnauthorized = () async => false;

    final response = await ApiClient.instance.sendGet(
      Uri.parse('https://example.test/api/v1/users/me'),
      client: client,
      headers: {'Authorization': 'Bearer stale-token'},
    );

    expect(response.statusCode, 401);
    expect(calls, 1);
  });
}
