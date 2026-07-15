import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../controllers/auth_controller.dart';
import '../../models/profile.dart';
import '../../services/oauth_sign_in_service.dart';
import 'settings_account_tab.dart';
import 'settings_app_tab.dart';
import 'settings_profile_tab.dart';

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
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  TabController? _tabController;
  int _selectedTabIndex = 0;
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _oauth = OAuthSignInService();

  Timer? _usernameCheckTimer;
  bool _isCheckingUsername = false;
  bool? _usernameAvailable;
  String? _usernameError;
  bool _isSaving = false;
  String? _saveError;
  bool _isUploadingImage = false;
  List<String> _linkedProviders = [];
  bool _isLoadingLinked = false;
  String? _activeLinkedProviderAction;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) return;
      setState(() => _selectedTabIndex = _tabController!.index);
    });
    _fullNameController.text = widget.currentUser.fullName ?? '';
    _usernameController.text = widget.currentUser.username ?? '';
    _emailController.text = widget.currentUser.email;
    _usernameController.addListener(_onUsernameChanged);
    _loadLinkedAccounts();
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _tabController?.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedAccounts() async {
    setState(() => _isLoadingLinked = true);
    try {
      final auth = context.read<AuthController>().authService;
      final providers = await auth.getLinkedAccounts();
      if (!mounted) return;
      setState(() => _linkedProviders = providers);
    } finally {
      if (mounted) setState(() => _isLoadingLinked = false);
    }
  }

  void _onUsernameChanged() {
    _usernameCheckTimer?.cancel();
    final value = _usernameController.text.trim();
    if (value == widget.currentUser.username) {
      setState(() {
        _usernameAvailable = true;
        _usernameError = null;
        _isCheckingUsername = false;
      });
      return;
    }
    if (value.length < 3) {
      setState(() {
        _usernameAvailable = null;
        _usernameError = null;
        _isCheckingUsername = false;
      });
      return;
    }
    setState(() {
      _isCheckingUsername = true;
      _usernameAvailable = null;
      _usernameError = null;
    });
    _usernameCheckTimer = Timer(const Duration(milliseconds: 500), () async {
      final result =
          await context.read<AuthController>().authService.checkUsername(value);
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _usernameAvailable = result['available'] == true;
        _usernameError = _usernameAvailable == true ? null : 'Username taken';
      });
    });
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _isUploadingImage = true);
    final bytes = await picked.readAsBytes();
    final result =
        await context.read<AuthController>().authService.uploadProfileImage(bytes);
    if (!mounted) return;
    setState(() => _isUploadingImage = false);
    if (result['success'] == true) {
      await context.read<AuthController>().applyUser(result['user'] as Profile);
      _showSnack('Profile photo updated');
    } else {
      _showSnack(result['message'] as String? ?? 'Upload failed');
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    if (_newPasswordController.text.isNotEmpty) {
      final hasPasswordLinked = _linkedProviders.contains('password');
      if (hasPasswordLinked && _currentPasswordController.text.isEmpty) {
        setState(() => _saveError = 'Current password is required');
        return;
      }
      if (_newPasswordController.text != _confirmPasswordController.text) {
        setState(() => _saveError = 'New passwords do not match');
        return;
      }
    }

    if (_usernameController.text.trim() != widget.currentUser.username &&
        _usernameAvailable != true) {
      setState(() => _saveError = 'Please wait for username check to finish');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final result = await context.read<AuthController>().authService.updateProfile(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          fullName: _fullNameController.text.trim(),
          currentPassword: _currentPasswordController.text.isEmpty
              ? null
              : _currentPasswordController.text,
          password: _newPasswordController.text.isEmpty
              ? null
              : _newPasswordController.text,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result['success'] == true) {
      await context.read<AuthController>().applyUser(result['user'] as Profile);
      _showSnack('Settings saved');
      Navigator.of(context).pop();
    } else {
      setState(() => _saveError = result['message'] as String? ?? 'Save failed');
    }
  }

  Future<void> _linkGoogle() async {
    if (kIsWeb) return;
    setState(() => _activeLinkedProviderAction = 'google');
    try {
      final google = await _oauth.signInWithGoogle(forceAccountPicker: true);
      if (google == null) {
        if (mounted) setState(() => _activeLinkedProviderAction = null);
        return;
      }
      final result = await context.read<AuthController>().authService.linkGoogle(
            idToken: google.idToken,
            accessToken: google.accessToken,
          );
      if (!mounted) return;
      setState(() => _activeLinkedProviderAction = null);
      if (result['success'] == true) {
        setState(
          () => _linkedProviders = (result['providers'] as List).cast<String>(),
        );
        _showSnack('Google linked');
      } else {
        _showSnack(result['message'] as String? ?? 'Link failed');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _activeLinkedProviderAction = null);
        _showSnack(error.toString());
      }
    }
  }

  Future<void> _linkApple() async {
    if (kIsWeb) return;
    setState(() => _activeLinkedProviderAction = 'apple');
    try {
      final apple = await _oauth.signInWithApple();
      if (apple?.idToken == null) {
        if (mounted) setState(() => _activeLinkedProviderAction = null);
        return;
      }
      final result = await context.read<AuthController>().authService.linkApple(
            idToken: apple!.idToken!,
            rawNonce: apple.rawNonce,
            authorizationCode: apple.authorizationCode,
          );
      if (!mounted) return;
      setState(() => _activeLinkedProviderAction = null);
      if (result['success'] == true) {
        setState(
          () => _linkedProviders = (result['providers'] as List).cast<String>(),
        );
        _showSnack('Apple linked');
      } else {
        _showSnack(result['message'] as String? ?? 'Link failed');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _activeLinkedProviderAction = null);
        _showSnack(error.toString());
      }
    }
  }

  Future<void> _unlinkProvider(String provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink account?'),
        content: Text('Unlink $provider? You can link it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Unlink',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _activeLinkedProviderAction = provider);
    final result =
        await context.read<AuthController>().authService.unlinkProvider(provider);
    if (!mounted) return;
    setState(() => _activeLinkedProviderAction = null);
    if (result['success'] == true) {
      setState(() => _linkedProviders = (result['providers'] as List).cast<String>());
    } else {
      _showSnack(result['message'] as String? ?? 'Unlink failed');
    }
  }

  Future<void> _requestDeleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This removes your progress and collections. Your account stays active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete data',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _showSnack('Delete data is not available yet');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This permanently deletes your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await context.read<AuthController>().authService.deleteAccount();
    if (!mounted) return;
    if (result['success'] == true) {
      await context.read<AuthController>().logout();
      if (mounted) Navigator.of(context).pop();
    } else {
      _showSnack(result['message'] as String? ?? 'Delete failed');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
