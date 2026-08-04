part of 'notification_icon_button.dart';

class _NotificationListContent extends StatelessWidget {
  const _NotificationListContent({
    required this.store,
    required this.onTapNotification,
    required this.onMarkAllRead,
  });

  final NotificationController store;
  final void Function(UserNotificationItem item) onTapNotification;
  final Future<void> Function() onMarkAllRead;

  static const double _listMaxHeight = 320.0;

  List<UserNotificationItem> _visibleItems() {
    final items = store.items.where((item) => item.isInAppBellItem).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems();
    final hasUnread = items.any((item) => !item.read);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        if (items.isNotEmpty && hasUnread)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onMarkAllRead,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  child: Text(
                    'Mark all as read',
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (items.isEmpty && store.isRefreshingInBackground)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No notifications yet',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _listMaxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: colorScheme.outline.withValues(alpha: 0.15),
                indent: 56,
                endIndent: 16,
              ),
              itemBuilder: (context, index) => _buildTile(
                context,
                items[index],
                onTapNotification,
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    UserNotificationItem item,
    void Function(UserNotificationItem) onTap,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timeText = DateFormat.Hm().format(item.createdAt.toLocal());

    if (item.isSiteDiscovered) {
      final label =
          item.siteLabel.isNotEmpty ? item.siteLabel : 'a field site';
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_outlined,
              color: item.read
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.primary,
            ),
            const SizedBox(height: 2),
            Text(
              timeText,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        title: Text(
          'You discovered $label',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: item.read ? FontWeight.normal : FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Tap to view card',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => onTap(item),
      );
    }

    if (item.isSiteDocumented) {
      final label =
          item.siteLabel.isNotEmpty ? item.siteLabel : 'a field site';
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              color: item.read
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.primary,
            ),
            const SizedBox(height: 2),
            Text(
              timeText,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        title: Text(
          'You documented $label',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: item.read ? FontWeight.normal : FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          'Tap to view card',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => onTap(item),
      );
    }

    final actor = item.actorUsername.isNotEmpty ? item.actorUsername : 'Someone';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_add_alt_1_outlined,
            color: item.read
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary,
          ),
          const SizedBox(height: 2),
          Text(
            timeText,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      title: Text(
        item.type == 'friend_request_accepted'
            ? '$actor accepted your friend request'
            : '$actor sent you a friend request',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: item.read ? FontWeight.normal : FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        item.type == 'friend_request_accepted'
            ? 'Tap to open profile'
            : 'Tap to review',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => onTap(item),
    );
  }
}
