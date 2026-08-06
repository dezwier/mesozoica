import 'package:mesozoica/models/profile.dart';
import 'package:mesozoica/models/user_list_entry.dart';
import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/core/networking/api_transport.dart';

class ProfileService {
  ProfileService({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<Profile> loadPublicProfile(int userId) async {
    final response = await _transport.get('/api/v1/users/$userId/profile');
    return Profile.fromJson(response);
  }
}

class UserDirectoryService {
  UserDirectoryService({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<({List<UserListEntry> items, int total, bool hasNext})> loadUsers({
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await _transport.get(
      '/api/v1/users/list',
      query: {'offset': '$offset', 'limit': '$limit'},
    );
    final items = (response['items'] as List<dynamic>? ?? const [])
        .map((item) => UserListEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return (
      items: items,
      total: response['total'] as int? ?? items.length,
      hasNext: response['has_next'] == true,
    );
  }
}
