import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/user_list_entry.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/user_relationship_service.dart';
import '../common/draggable_sheet_wrapper.dart';
import 'profile_content.dart';

class CommunityDrawer extends StatefulWidget {
  const CommunityDrawer({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  State<CommunityDrawer> createState() => _CommunityDrawerState();
}

class _CommunityDrawerState extends State<CommunityDrawer> {
  static const _pageSize = 5;
  final _friendsService = UserRelationshipService();
  final _directoryService = UserDirectoryService();

  final _friendsSearchController = TextEditingController();
  final _paleontologistsSearchController = TextEditingController();

  List<UserListEntry> _friends = [];
  List<UserListEntry> _paleontologists = [];
  int _friendsTotal = 0;
  int _paleontologistsTotal = 0;
  bool _loadingFriends = true;
  bool _loadingPaleontologists = true;
  bool _loadingMoreFriends = false;
  bool _loadingMorePaleontologists = false;

  @override
  void initState() {
    super.initState();
    _friendsSearchController.addListener(() => setState(() {}));
    _paleontologistsSearchController.addListener(() => setState(() {}));
    _loadFriends();
    _loadPaleontologists();
  }

  @override
  void dispose() {
    _friendsSearchController.dispose();
    _paleontologistsSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _loadingMoreFriends = true);
    } else {
      setState(() => _loadingFriends = true);
    }
    try {
      final result = await _friendsService.fetchFriends(
        offset: loadMore ? _friends.length : 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _friends = [..._friends, ...result.entries];
        } else {
          _friends = result.entries;
        }
        _friendsTotal = result.total;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingFriends = false;
          _loadingMoreFriends = false;
        });
      }
    }
  }

  Future<void> _loadPaleontologists({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _loadingMorePaleontologists = true);
    } else {
      setState(() => _loadingPaleontologists = true);
    }
    try {
      final result = await _directoryService.loadUsers(
        offset: loadMore ? _paleontologists.length : 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _paleontologists = [..._paleontologists, ...result.items];
        } else {
          _paleontologists = result.items;
        }
        _paleontologistsTotal = result.total;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPaleontologists = false;
          _loadingMorePaleontologists = false;
        });
      }
    }
  }

  bool _matches(UserListEntry entry, String query) {
    if (query.isEmpty) return true;
    final haystack =
        '${entry.username} ${entry.displayName} ${entry.fullName ?? ''}'.toLowerCase();
    return haystack.contains(query.toLowerCase());
  }

  void _openUser(UserListEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableSheetWrapper(
        childBuilder: (scrollController) => UserProfileDrawer(
          userId: entry.id,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsQuery = _friendsSearchController.text.trim();
    final paleoQuery = _paleontologistsSearchController.text.trim();
    final filteredFriends =
        _friends.where((entry) => _matches(entry, friendsQuery)).toList();
    final filteredPaleontologists =
        _paleontologists.where((entry) => _matches(entry, paleoQuery)).toList();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Community', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          _sectionHeader('Friends', Icons.people, _friendsSearchController),
          const SizedBox(height: 8),
          if (_loadingFriends)
            const Center(child: CircularProgressIndicator())
          else if (filteredFriends.isEmpty)
            Text('No friends yet.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            ...filteredFriends.map((entry) => _userTile(entry)),
          if (!_loadingFriends &&
              friendsQuery.isEmpty &&
              _friends.length < _friendsTotal)
            TextButton(
              onPressed:
                  _loadingMoreFriends ? null : () => _loadFriends(loadMore: true),
              child: _loadingMoreFriends
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load more'),
            ),
          const SizedBox(height: 24),
          _sectionHeader(
            'Paleontologists',
            Icons.people_outline,
            _paleontologistsSearchController,
          ),
          const SizedBox(height: 8),
          if (_loadingPaleontologists)
            const Center(child: CircularProgressIndicator())
          else if (filteredPaleontologists.isEmpty)
            Text('No paleontologists found.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            ...filteredPaleontologists.map((entry) => _userTile(entry)),
          if (!_loadingPaleontologists &&
              paleoQuery.isEmpty &&
              _paleontologists.length < _paleontologistsTotal)
            TextButton(
              onPressed: _loadingMorePaleontologists
                  ? null
                  : () => _loadPaleontologists(loadMore: true),
              child: _loadingMorePaleontologists
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load more'),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Search',
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _userTile(UserListEntry entry) {
    final imageUrl = AuthService.imageUrl(entry.imageUrl);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage:
            imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
        child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(entry.displayName),
      subtitle: Text('@${entry.username} · Lv.${entry.level}'),
      onTap: () => _openUser(entry),
    );
  }
}

class UserProfileDrawer extends StatefulWidget {
  const UserProfileDrawer({
    super.key,
    required this.userId,
    this.scrollController,
  });

  final int userId;
  final ScrollController? scrollController;

  @override
  State<UserProfileDrawer> createState() => _UserProfileDrawerState();
}

class _UserProfileDrawerState extends State<UserProfileDrawer> {
  final _profileService = ProfileService();
  final _relationshipService = UserRelationshipService();

  bool _loading = true;
  bool _friendBusy = false;
  String? _error;
  Profile? _profile;
  Map<String, dynamic>? _relationship;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _profileService.loadPublicProfile(widget.userId);
      final relationship =
          await _relationshipService.fetchRelationship(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _relationship = relationship;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _relationshipType =>
      _relationship?['relationship_type'] as String? ?? 'none';

  int? get _actionUserId => _relationship?['action_user_id'] as int?;

  Future<void> _handleFriendAction() async {
    if (_friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      if (_relationshipType == 'none') {
        _relationship =
            await _relationshipService.sendFriendRequest(widget.userId);
      } else if (_relationshipType == 'friend_pending' &&
          _actionUserId != null) {
        _relationship = await _relationshipService
            .cancelFriendRequest(widget.userId);
      } else if (_relationshipType == 'friend') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove friend?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove')),
            ],
          ),
        );
        if (confirmed == true) {
          _relationship =
              await _relationshipService.removeFriend(widget.userId);
        }
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  IconData _friendIcon() {
    switch (_relationshipType) {
      case 'friend':
        return Icons.person_remove_outlined;
      case 'friend_pending':
        return Icons.hourglass_top_outlined;
      default:
        return Icons.person_add_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _profile == null
                  ? const Center(child: Text('Profile unavailable'))
                  : ListView(
                  controller: widget.scrollController,
                  children: [
                    ProfileContent(
                      profile: _profile!,
                      headerActions: IconButton(
                        onPressed: _friendBusy ? null : _handleFriendAction,
                        icon: _friendBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_friendIcon()),
                      ),
                    ),
                  ],
                ),
    );
  }
}
