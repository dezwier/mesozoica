import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/user_list_entry.dart';
import '../../services/auth_service.dart';

/// User row for community section cards (Archipelago layout).
class UserListItem extends StatelessWidget {
  const UserListItem({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final UserListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AuthService.imageUrl(entry.imageUrl);
    final displayName = entry.fullName?.isNotEmpty == true
        ? entry.fullName!
        : entry.displayName;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: imageUrl.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 35,
                        height: 35,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Icon(
                          Icons.person,
                          size: 35,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 35,
                      color: Theme.of(context).colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${entry.username}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
