import 'package:mesozoica/models/user_list_entry.dart';
import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/core/networking/api_transport.dart';

class UserRelationshipService {
  UserRelationshipService({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<Map<String, dynamic>> fetchRelationship(int targetUserId) async {
    return _transport.get('/api/v1/user-relationships/$targetUserId');
  }

  Future<Map<String, dynamic>> sendFriendRequest(int targetUserId) async {
    return _transport.post(
      '/api/v1/user-relationships/friend-request',
      body: {'target_user_id': targetUserId},
    );
  }

  Future<Map<String, dynamic>> cancelFriendRequest(int targetUserId) async {
    return _transport.post(
      '/api/v1/user-relationships/friend-request/$targetUserId/cancel',
    );
  }

  Future<Map<String, dynamic>> acceptFriendRequest(int targetUserId) async {
    return _transport.post(
      '/api/v1/user-relationships/friend-request/$targetUserId/accept',
    );
  }

  Future<Map<String, dynamic>> rejectFriendRequest(int targetUserId) async {
    return _transport.post(
      '/api/v1/user-relationships/friend-request/$targetUserId/reject',
    );
  }

  Future<Map<String, dynamic>> removeFriend(int targetUserId) async {
    return _transport.post(
      '/api/v1/user-relationships/friend/$targetUserId/remove',
    );
  }

  Future<({List<UserListEntry> entries, int total})> fetchFriends({
    int offset = 0,
    int limit = 5,
  }) async {
    final response = await _transport.get(
      '/api/v1/user-relationships/friends/me/list',
      query: {'offset': '$offset', 'limit': '$limit'},
    );
    final entries = (response['entries'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              UserListEntry.fromLeaderboardUser(item as Map<String, dynamic>),
        )
        .toList();
    return (
      entries: entries,
      total: response['total'] as int? ?? entries.length,
    );
  }
}
