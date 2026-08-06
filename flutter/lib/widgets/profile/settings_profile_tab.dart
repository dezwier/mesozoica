import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import 'settings_form_styles.dart';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finePrintStyle = SettingsFormStyles.finePrintStyle(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Profile',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Update your photo, username, and display name.',
                        style: finePrintStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Consumer<AuthController>(
                  builder: (context, auth, _) {
                    final user = auth.currentUser ?? currentUser;
                    final imageUrl = AuthService.imageUrl(user.profileImage);
                    return GestureDetector(
                      onTap: isUploadingImage ? null : onPickImage,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primaryContainer,
                        ),
                        child: isUploadingImage
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    scheme.primary,
                                  ),
                                ),
                              )
                            : imageUrl.isNotEmpty
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) => Icon(
                                    Icons.person,
                                    size: 64,
                                    color: scheme.primary,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person,
                                size: 64,
                                color: scheme.primary,
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: usernameController,
              decoration: SettingsFormStyles.createStyleDecoration(
                context,
                labelText: 'Username',
                suffixIcon: isCheckingUsername
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : usernameAvailable == true
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : usernameAvailable == false
                    ? const Icon(Icons.cancel, color: Colors.red)
                    : null,
                errorText: usernameError,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: fullNameController,
              decoration: SettingsFormStyles.createStyleDecoration(
                context,
                labelText: 'Full name',
                counterText: '',
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 200,
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }
}
