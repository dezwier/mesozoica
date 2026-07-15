import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/auth_service.dart';

class SettingsProfileTab extends StatelessWidget {
  const SettingsProfileTab({
    super.key,
    required this.currentUser,
    required this.fullNameController,
    required this.usernameController,
    required this.usernameAvailable,
    required this.usernameError,
    required this.isCheckingUsername,
    required this.isUploadingImage,
    required this.onPickImage,
  });

  final Profile currentUser;
  final TextEditingController fullNameController;
  final TextEditingController usernameController;
  final bool? usernameAvailable;
  final String? usernameError;
  final bool isCheckingUsername;
  final bool isUploadingImage;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AuthService.imageUrl(currentUser.profileImage);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: imageUrl.isNotEmpty
                      ? CachedNetworkImageProvider(imageUrl)
                      : null,
                  child: imageUrl.isEmpty
                      ? const Icon(Icons.person, size: 42)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    onPressed: isUploadingImage ? null : onPickImage,
                    icon: isUploadingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              errorText: usernameError,
              suffixIcon: isCheckingUsername
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : usernameAvailable == true
                      ? const Icon(Icons.check_circle_outline, color: Colors.green)
                      : usernameAvailable == false
                          ? const Icon(Icons.cancel_outlined, color: Colors.red)
                          : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fullNameController,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}
