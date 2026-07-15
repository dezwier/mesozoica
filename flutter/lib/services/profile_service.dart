import '../models/profile.dart';
import '../models/user_list_entry.dart';
import 'api_client.dart';

class ProfileService {
  Future<Profile> loadPublicProfile(int userId) async {
    final response = await ApiClient.instance.get('/api/v1/users/$userId/profile');
    return Profile.fromJson(response);
  }
}

class UserDirectoryService {
  Future<({List<UserListEntry> items, int total, bool hasNext})> loadUsers({
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await ApiClient.instance.get(
      '/api/v1/users/list',
      query: {
        'offset': '$offset',
        'limit': '$limit',
      },
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
