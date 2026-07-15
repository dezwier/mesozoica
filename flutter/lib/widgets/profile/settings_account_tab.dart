import 'package:flutter/material.dart';

import '../../models/profile.dart';

class SettingsAccountTab extends StatelessWidget {
  const SettingsAccountTab({
    super.key,
    required this.currentUser,
    required this.emailController,
    required this.currentPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.linkedAccountRows,
    required this.isLoadingLinked,
    required this.onRequestDeleteAccount,
  });

  final Profile currentUser;
  final TextEditingController emailController;
  final TextEditingController currentPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final List<Widget> linkedAccountRows;
  final bool isLoadingLinked;
  final VoidCallback onRequestDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Subscription', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Chip(
                label: const Text('Free'),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: currentPasswordController,
            decoration: const InputDecoration(labelText: 'Current password'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newPasswordController,
            decoration: const InputDecoration(labelText: 'New password'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmPasswordController,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          Text('Sign-in methods', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (isLoadingLinked)
            const Center(child: CircularProgressIndicator())
          else
            ...linkedAccountRows,
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: onRequestDeleteAccount,
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Delete account'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}
