import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../models/profile.dart';
import '../../models/user_list_entry.dart';
import '../../services/profile_service.dart';
import '../../services/user_relationship_service.dart';
import '../common/draggable_sheet_wrapper.dart';
import '../common/drawer_sheet_sizes.dart';
import '../common/section_card.dart';
import 'profile_content.dart';
import 'user_list_item.dart';

part 'user_profile_drawer.dart';

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
  final _friendsSearchFocusNode = FocusNode();
  final _paleontologistsSearchController = TextEditingController();
  final _paleontologistsSearchFocusNode = FocusNode();

  List<UserListEntry> _friends = [];
  List<UserListEntry> _paleontologists = [];
  int _friendsTotal = 0;
  int _paleontologistsTotal = 0;
  bool _loadingFriends = true;
  bool _loadingPaleontologists = true;
  bool _loadingMoreFriends = false;
  bool _loadingMorePaleontologists = false;
  String _friendsSearchQuery = '';
  String _paleontologistsSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _friendsSearchController.addListener(() {
      setState(() {
        _friendsSearchQuery = _friendsSearchController.text
            .trim()
            .toLowerCase();
      });
    });
    _paleontologistsSearchController.addListener(() {
      setState(() {
        _paleontologistsSearchQuery = _paleontologistsSearchController.text
            .trim()
            .toLowerCase();
      });
    });
    _loadFriends();
    _loadPaleontologists();
  }

  @override
  void dispose() {
    _friendsSearchController.dispose();
    _friendsSearchFocusNode.dispose();
    _paleontologistsSearchController.dispose();
    _paleontologistsSearchFocusNode.dispose();
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
    final username = entry.username.toLowerCase();
    final fullName = (entry.fullName ?? '').toLowerCase();
    final displayName = entry.displayName.toLowerCase();
    return username.contains(query) ||
        fullName.contains(query) ||
        displayName.contains(query);
  }

  void _openUser(UserListEntry entry) {
    showUserProfileSheet(context, entry.id);
  }

  Widget _buildUserSearchField({
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        hintText: 'Search',
        isDense: true,
        isCollapsed: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
    );
  }

  Widget _buildSectionHeaderWithInlineSearch({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: _buildUserSearchField(
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsSection() {
    final filteredEntries = _friends
        .where((entry) => _matches(entry, _friendsSearchQuery))
        .toList();
    final isSearching = _friendsSearchQuery.isNotEmpty;
    final noResultsMessage = isSearching
        ? 'No friends match your search'
        : 'No friends yet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeaderWithInlineSearch(
          title: 'Friends',
          icon: Icons.people,
          controller: _friendsSearchController,
          focusNode: _friendsSearchFocusNode,
        ),
        if (!_loadingFriends && filteredEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              noResultsMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          SectionCard<UserListEntry>(
            title: 'Friends',
            titleIcon: Icons.people,
            items: filteredEntries,
            isLoading: _loadingFriends,
            initialVisibleCount: _pageSize,
            total: isSearching ? filteredEntries.length : _friendsTotal,
            onLoadMore: isSearching ? null : () => _loadFriends(loadMore: true),
            isLoadingMore: isSearching ? false : _loadingMoreFriends,
            showVerticalTitle: false,
            itemBuilder: (context, entry, index) {
              return UserListItem(entry: entry, onTap: () => _openUser(entry));
            },
          ),
      ],
    );
  }

  Widget _buildPaleontologistsSection() {
    final filteredEntries = _paleontologists
        .where((entry) => _matches(entry, _paleontologistsSearchQuery))
        .toList();
    final isSearching = _paleontologistsSearchQuery.isNotEmpty;
    final noResultsMessage = isSearching
        ? 'No paleontologists match your search'
        : 'No paleontologists yet';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeaderWithInlineSearch(
          title: 'Paleontologists',
          icon: Icons.people_outline,
          controller: _paleontologistsSearchController,
          focusNode: _paleontologistsSearchFocusNode,
        ),
        if (!_loadingPaleontologists && filteredEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              noResultsMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          )
        else
          SectionCard<UserListEntry>(
            title: 'Paleontologists',
            titleIcon: Icons.people_outline,
            items: filteredEntries,
            isLoading: _loadingPaleontologists,
            initialVisibleCount: _pageSize,
            total: isSearching ? filteredEntries.length : _paleontologistsTotal,
            onLoadMore: isSearching
                ? null
                : () => _loadPaleontologists(loadMore: true),
            isLoadingMore: isSearching ? false : _loadingMorePaleontologists,
            showVerticalTitle: false,
            itemBuilder: (context, entry, index) {
              return UserListItem(entry: entry, onTap: () => _openUser(entry));
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.scrollController != null
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height *
                  DrawerSheetSizes.initialChildSize;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).viewInsets.bottom + 8
                  : 0,
            ),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          'Community',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: widget.scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        _buildFriendsSection(),
                        _buildPaleontologistsSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
