import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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
    if (value.length < 3 || value == widget.currentUser.username) {
      setState(() {
        _usernameAvailable = value == widget.currentUser.username ? true : null;
        _usernameError = null;
      });
      return;
    }
    _usernameCheckTimer = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isCheckingUsername = true);
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
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnack('New passwords do not match');
      return;
    }
    setState(() => _isSaving = true);
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
      _showSnack(result['message'] as String? ?? 'Save failed');
    }
  }

  Future<void> _linkGoogle() async {
    if (kIsWeb) return;
    setState(() => _activeLinkedProviderAction = 'google');
    try {
      final idToken = await _oauth.signInWithGoogle();
      if (idToken == null) return;
      final credential = await _oauth.firebaseSignInWithGoogle(idToken);
      final token = await credential.user?.getIdToken(true);
      if (token == null) return;
      final result =
          await context.read<AuthController>().authService.linkGoogle(token);
      if (result['success'] == true) {
        setState(
          () => _linkedProviders = (result['providers'] as List).cast<String>(),
        );
        _showSnack('Google linked');
      } else {
        _showSnack(result['message'] as String? ?? 'Link failed');
      }
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _activeLinkedProviderAction = null);
    }
  }

  Future<void> _linkApple() async {
    if (kIsWeb) return;
    setState(() => _activeLinkedProviderAction = 'apple');
    try {
      final apple = await _oauth.signInWithApple();
      if (apple?.idToken == null) return;
      final credential = await _oauth.firebaseSignInWithApple(
        idToken: apple!.idToken!,
        rawNonce: apple.rawNonce,
      );
      final token = await credential.user?.getIdToken(true);
      if (token == null) return;
      final result =
          await context.read<AuthController>().authService.linkApple(token);
      if (result['success'] == true) {
        setState(
          () => _linkedProviders = (result['providers'] as List).cast<String>(),
        );
        _showSnack('Apple linked');
      } else {
        _showSnack(result['message'] as String? ?? 'Link failed');
      }
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _activeLinkedProviderAction = null);
    }
  }

  Future<void> _unlinkProvider(String provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink $provider?'),
        content: const Text('You can link it again later in Account settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unlink')),
        ],
      ),
    );
    if (confirmed != true) return;
    final result =
        await context.read<AuthController>().authService.unlinkProvider(provider);
    if (result['success'] == true) {
      setState(() => _linkedProviders = (result['providers'] as List).cast<String>());
    } else {
      _showSnack(result['message'] as String? ?? 'Unlink failed');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This permanently deletes your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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

  List<Widget> _buildLinkedRows() {
    const providers = ['password', 'google', 'apple'];
    return providers.map((provider) {
      final linked = _linkedProviders.contains(provider);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_providerLabel(provider)),
        trailing: linked
            ? TextButton(
                onPressed: _linkedProviders.length <= 1
                    ? null
                    : () => _unlinkProvider(provider),
                child: const Text('Unlink'),
              )
            : TextButton(
                onPressed: _activeLinkedProviderAction != null
                    ? null
                    : provider == 'google'
                        ? _linkGoogle
                        : provider == 'apple'
                            ? _linkApple
                            : null,
                child: Text(
                  _activeLinkedProviderAction == provider ? 'Linking…' : 'Link',
                ),
              ),
      );
    }).toList();
  }

  String _providerLabel(String provider) {
    switch (provider) {
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      default:
        return 'Password';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'App'),
              Tab(text: 'Profile'),
              Tab(text: 'Account'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SettingsAppTab(),
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
                  emailController: _emailController,
                  currentPasswordController: _currentPasswordController,
                  newPasswordController: _newPasswordController,
                  confirmPasswordController: _confirmPasswordController,
                  linkedAccountRows: _buildLinkedRows(),
                  isLoadingLinked: _isLoadingLinked,
                  onRequestDeleteAccount: _confirmDeleteAccount,
                ),
              ],
            ),
          ),
          if (_selectedTabIndex != 0)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
