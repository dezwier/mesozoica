import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/map_controller.dart';
import '../../controllers/site_catalog_controller.dart';
import '../../models/profile.dart';
import '../../services/api_response_cache.dart';
import '../../services/oauth_sign_in_service.dart';
import 'delete_data_dialog.dart';
import 'settings_account_tab.dart';
import 'settings_app_tab.dart';
import 'settings_profile_tab.dart';

part 'account_settings_sheet_logic.dart';

class AccountSettingsSheet extends StatefulWidget {
  const AccountSettingsSheet({
    super.key,
    required this.currentUser,
    this.scrollController,
  });

  final Profile currentUser;
  final ScrollController? scrollController;

  @override
  State<AccountSettingsSheet> createState() => _AccountSettingsSheetState();
}

class _AccountSettingsSheetState extends State<AccountSettingsSheet>
    with TickerProviderStateMixin, _AccountSettingsSheetLogicMixin {
  TabController? _tabController;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) return;
      setState(() => _selectedTabIndex = _tabController!.index);
    });
    _initLogicMixin();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _disposeLogicMixin();
    super.dispose();
  }

  List<Widget> _buildLinkedAccountsRows(BuildContext context) {
    final hasPassword = _linkedProviders.contains('password');
    final hasGoogle = _linkedProviders.contains('google');
    final hasApple = _linkedProviders.contains('apple');
    final canUnlink = _linkedProviders.length > 1;

    return [
      _linkedAccountRow(
        context,
        providerKey: 'password',
        label: 'Password',
        buttonLabel: hasPassword ? 'Unlink' : 'Link',
        onAction: hasPassword
            ? (canUnlink ? () => _unlinkProvider('password') : null)
            : null,
        isDestructiveAction: hasPassword,
        isLoading: _activeLinkedProviderAction == 'password',
      ),
      _linkedAccountRow(
        context,
        providerKey: 'google',
        label: 'Google',
        buttonLabel: hasGoogle ? 'Unlink' : 'Link',
        onAction: hasGoogle
            ? (canUnlink ? () => _unlinkProvider('google') : null)
            : _linkGoogle,
        isDestructiveAction: hasGoogle,
        isLoading: _activeLinkedProviderAction == 'google',
      ),
      if (AppConfig.enableAppleSignIn || hasApple)
        _linkedAccountRow(
          context,
          providerKey: 'apple',
          label: 'Apple',
          buttonLabel: hasApple ? 'Unlink' : 'Link',
          onAction: hasApple
              ? (canUnlink ? () => _unlinkProvider('apple') : null)
              : _linkApple,
          isDestructiveAction: hasApple,
          isLoading: _activeLinkedProviderAction == 'apple',
        ),
    ];
  }

  Widget _linkedAccountRow(
    BuildContext context, {
    required String providerKey,
    required String label,
    required String buttonLabel,
    required VoidCallback? onAction,
    required bool isDestructiveAction,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLinked = isDestructiveAction;
    final icon = providerKey == 'password'
        ? Icons.lock_outline
        : (providerKey == 'google' ? Icons.g_mobiledata : Icons.apple);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurface),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IgnorePointer(
            ignoring: isLoading,
            child: FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(isLinked ? Icons.link_off : Icons.link),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor:
                    isLinked ? colorScheme.error : colorScheme.primary,
                backgroundColor: isLinked
                    ? colorScheme.errorContainer.withValues(alpha: 0.45)
                    : colorScheme.primaryContainer.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _tabController;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.scrollController != null
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height * 0.9;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
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
              TabBar(
                controller: controller,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
                tabs: const [
                  Tab(text: 'App'),
                  Tab(text: 'Profile'),
                  Tab(text: 'Account'),
                ],
              ),
              Flexible(
                child: Form(
                  key: _formKey,
                  child: TabBarView(
                    controller: controller,
                    children: [
                      const SettingsAppTab(),
                      SettingsProfileTab(
                        currentUser: widget.currentUser,
                        fullNameController: _fullNameController,
                        usernameController: _usernameController,
                        usernameAvailable: _usernameAvailable,
                        usernameError: _usernameError,
                        isCheckingUsername: _isCheckingUsername,
                        isUploadingImage: _isUploadingImage,
                        onPickImage: _pickImage,
                      ),
                      SettingsAccountTab(
                        currentUser: widget.currentUser,
                        scrollController: widget.scrollController,
                        emailController: _emailController,
                        currentPasswordController: _currentPasswordController,
                        newPasswordController: _newPasswordController,
                        confirmPasswordController: _confirmPasswordController,
                        emailValidator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!value.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                        newPasswordValidator: (value) {
                          if (_newPasswordController.text.isNotEmpty &&
                              (value == null || value.length < 6)) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        confirmPasswordValidator: (value) {
                          if (_newPasswordController.text.isNotEmpty &&
                              value != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                        linkedAccountRows: _buildLinkedAccountsRows(context),
                        isLoadingLinked: _isLoadingLinked,
                        onRequestDeleteAllData: _requestDeleteAllData,
                        onRequestDeleteAccount: _confirmDeleteAccount,
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedTabIndex != 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_saveError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _saveError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _isSaving ? null : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveSettings,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
