import 'package:flutter/material.dart';

import '../../models/profile.dart';
import 'settings_form_styles.dart';

class SettingsAccountTab extends StatelessWidget {
  const SettingsAccountTab({
    super.key,
    required this.currentUser,
    required this.scrollController,
    required this.emailController,
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.emailValidator,
    required this.newPasswordValidator,
    required this.confirmPasswordValidator,
    required this.linkedAccountRows,
    required this.isLoadingLinked,
    required this.onRequestDeleteAccount,
    this.onRequestDeleteAllData,
  });

  final Profile currentUser;
  final ScrollController? scrollController;
  final TextEditingController emailController;
  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final String? Function(String?) emailValidator;
  final String? Function(String?) newPasswordValidator;
  final String? Function(String?) confirmPasswordValidator;
  final List<Widget> linkedAccountRows;
  final bool isLoadingLinked;
  final VoidCallback onRequestDeleteAccount;
  final VoidCallback? onRequestDeleteAllData;

  @override
  Widget build(BuildContext context) {
    const isFree = true;

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Subscription status',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (isFree) ...[
                const Expanded(
                  child: _SubscriptionChip(
                    label: 'Free',
                    isSelected: true,
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              const Expanded(
                child: _SubscriptionChip(
                  label: 'Premium',
                  isSelected: false,
                  icon: Icons.workspace_premium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Email and password',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: emailController,
            decoration: SettingsFormStyles.createStyleDecoration(
              context,
              labelText: 'Email',
            ),
            keyboardType: TextInputType.emailAddress,
            validator: emailValidator,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: currentPasswordController,
            decoration: SettingsFormStyles.createStyleDecoration(
              context,
              labelText: 'Current password',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: newPasswordController,
            decoration: SettingsFormStyles.createStyleDecoration(
              context,
              labelText: 'New password',
            ),
            obscureText: true,
            validator: newPasswordValidator,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: confirmPasswordController,
            decoration: SettingsFormStyles.createStyleDecoration(
              context,
              labelText: 'Confirm new password',
            ),
            obscureText: true,
            validator: confirmPasswordValidator,
          ),
          const SizedBox(height: 24),
          Text(
            'Sign-in methods',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          if (isLoadingLinked)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ...linkedAccountRows,
          const SizedBox(height: 20),
          Text(
            'Delete',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRequestDeleteAllData,
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Delete data'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRequestDeleteAccount,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete account'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

class _SubscriptionChip extends StatelessWidget {
  const _SubscriptionChip({
    required this.label,
    required this.isSelected,
    required this.icon,
  });

  final String label;
  final bool isSelected;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final outline = Theme.of(context).colorScheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: isSelected ? primary.withValues(alpha: 0.12) : surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primary : outline.withValues(alpha: 0.3),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected ? primary : outline,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? primary : outline,
                ),
          ),
        ],
      ),
    );
  }
}
