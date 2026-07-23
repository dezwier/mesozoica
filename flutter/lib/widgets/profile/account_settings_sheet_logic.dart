part of 'account_settings_sheet.dart';

/// Linked sign-in providers, profile-form operations (username check, image
/// upload, save), and account/data deletion for [AccountSettingsSheet].
mixin _AccountSettingsSheetLogicMixin on State<AccountSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
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

  void _initLogicMixin() {
    _fullNameController.text = widget.currentUser.fullName ?? '';
    _usernameController.text = widget.currentUser.username ?? '';
    _emailController.text = widget.currentUser.email;
    _usernameController.addListener(_onUsernameChanged);
    _loadLinkedAccounts();
  }

  void _disposeLogicMixin() {
    _usernameCheckTimer?.cancel();
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
  }

  Future<void> _loadLinkedAccounts() async {
    setState(() => _isLoadingLinked = true);
    try {
      final auth = context.read<AuthController>();
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
          await context.read<AuthController>().checkUsername(value);
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
        await context.read<AuthController>().uploadProfileImage(bytes);
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

    final result = await context.read<AuthController>().updateProfile(
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
      final result = await context.read<AuthController>().linkGoogle(
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
      final result = await context.read<AuthController>().linkApple(
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
        await context.read<AuthController>().unlinkProvider(provider);
    if (!mounted) return;
    setState(() => _activeLinkedProviderAction = null);
    if (result['success'] == true) {
      setState(() => _linkedProviders = (result['providers'] as List).cast<String>());
    } else {
      _showSnack(result['message'] as String? ?? 'Unlink failed');
    }
  }

  Future<void> _requestDeleteAllData() async {
    final auth = context.read<AuthController>();
    try {
      await auth.refreshProfile();
    } catch (_) {
      // Still show dialog with cached counts if refresh fails.
    }
    if (!mounted) return;

    final profile = auth.currentUser ?? widget.currentUser;
    final selection = await showDialog<DeleteDataSelection>(
      context: context,
      builder: (ctx) => DeleteDataDialog(profile: profile),
    );
    if (selection == null || !selection.hasAny || !mounted) return;

    final result = await auth.deleteData(
      sites: selection.sites,
      fossils: selection.fossils,
      dinosaurs: selection.dinosaurs,
    );
    if (!mounted) return;

    if (result['success'] != true) {
      _showSnack(result['message'] as String? ?? 'Delete failed');
      return;
    }

    final updated = result['user'] as Profile?;
    if (updated != null) {
      await auth.applyUser(updated);
    } else {
      await auth.refreshProfile();
    }
    if (!mounted) return;

    final userId = auth.currentUser?.id ?? profile.id;
    await ApiResponseCache.instance.clearForUser(userId);
    if (!mounted) return;

    final isAdmin = auth.currentUser?.isAdmin ?? false;
    context.read<MapController>().onUserChanged(isAdmin: isAdmin);
    context.read<ToolCatalogController>().onUserChanged(isAdmin: isAdmin);
    context.read<FieldDiscoveryCoordinator>().clearForUserChange();
    unawaited(
      context
          .read<FieldDiscoveryCoordinator>()
          .refreshDiscoverableCache(force: true),
    );
    context.read<SiteCatalogController>().load(force: true);
    context.read<ToolCatalogController>().load(force: true);

    final parts = <String>[];
    if (selection.sites) {
      parts.add('${result['deleted_sites'] ?? 0} site rows');
    }
    if (selection.fossils) {
      parts.add('${result['deleted_fossils'] ?? 0} fossil rows');
    }
    if (selection.dinosaurs) {
      parts.add('${result['deleted_dinosaurs'] ?? 0} dino rows');
    }
    _showSnack(
      parts.isEmpty ? 'Data deleted' : 'Deleted ${parts.join(', ')}',
    );
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
    final result = await context.read<AuthController>().deleteAccount();
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
}
