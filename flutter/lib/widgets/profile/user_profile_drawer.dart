part of 'community_drawer.dart';

void showUserProfileSheet(
  BuildContext context,
  int userId, {
  bool showFriendRequestActions = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableSheetWrapper(
      childBuilder: (scrollController) => UserProfileDrawer(
        userId: userId,
        scrollController: scrollController,
        showFriendRequestActions: showFriendRequestActions,
      ),
    ),
  );
}

class UserProfileDrawer extends StatefulWidget {
  const UserProfileDrawer({
    super.key,
    required this.userId,
    this.scrollController,
    this.showFriendRequestActions = false,
  });

  final int userId;
  final ScrollController? scrollController;
  final bool showFriendRequestActions;

  @override
  State<UserProfileDrawer> createState() => _UserProfileDrawerState();
}

class _UserProfileDrawerState extends State<UserProfileDrawer> {
  final _profileService = ProfileService();
  final _relationshipService = UserRelationshipService();

  bool _loading = true;
  bool _friendBusy = false;
  bool _friendDecisionBusy = false;
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
      final currentUserId = context.read<AuthController>().currentUser?.id;
      final profile = await _profileService.loadPublicProfile(widget.userId);
      final relationship = currentUserId == widget.userId
          ? {'relationship_type': 'self'}
          : await _relationshipService.fetchRelationship(widget.userId);
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

  int? get _currentUserId => context.read<AuthController>().currentUser?.id;

  bool get _isOutgoingPending =>
      _relationshipType == 'friend_pending' &&
      _actionUserId != null &&
      _actionUserId == _currentUserId;

  bool get _showIncomingFriendRequestActions {
    if (!widget.showFriendRequestActions) return false;
    if (_relationshipType == 'friend_pending' &&
        _actionUserId != null &&
        _actionUserId != _currentUserId) {
      return true;
    }
    return _relationship == null && widget.showFriendRequestActions;
  }

  Future<void> _refreshNotifications() async {
    final userId = _currentUserId;
    if (userId == null || !mounted) return;
    await context
        .read<NotificationController>()
        .refreshInBackground(authenticatedUserId: userId);
  }

  Future<void> _handleFriendAction() async {
    if (_friendBusy) return;
    setState(() => _friendBusy = true);
    try {
      if (_relationshipType == 'none') {
        _relationship =
            await _relationshipService.sendFriendRequest(widget.userId);
        await _refreshNotifications();
      } else if (_isOutgoingPending) {
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
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove'),
              ),
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

  Future<void> _acceptFriendRequest() async {
    if (_friendDecisionBusy) return;
    setState(() => _friendDecisionBusy = true);
    try {
      _relationship =
          await _relationshipService.acceptFriendRequest(widget.userId);
      await _refreshNotifications();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _friendDecisionBusy = false);
    }
  }

  Future<void> _rejectFriendRequest() async {
    if (_friendDecisionBusy) return;
    setState(() => _friendDecisionBusy = true);
    try {
      _relationship =
          await _relationshipService.rejectFriendRequest(widget.userId);
      await _refreshNotifications();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _friendDecisionBusy = false);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.scrollController != null
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height * 0.9;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: _buildBody(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_profile == null) {
      return const Center(child: Text('Profile unavailable'));
    }

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_showIncomingFriendRequestActions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _friendDecisionBusy ? null : _rejectFriendRequest,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _friendDecisionBusy ? null : _acceptFriendRequest,
                    child: _friendDecisionBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ),
        ProfileContent(
          profile: _profile!,
          headerActions: _relationshipType == 'self' || _showIncomingFriendRequestActions
              ? null
              : (_relationshipType == 'friend_pending' && !_isOutgoingPending)
                  ? null
                  : IconButton(
                      onPressed: _friendBusy ? null : _handleFriendAction,
                      icon: _friendBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_friendIcon()),
                    ),
        ),
      ],
    );
  }
}
