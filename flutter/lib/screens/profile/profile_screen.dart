import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/profile.dart';
import '../../services/oauth_sign_in_service.dart';
import '../../widgets/common/draggable_sheet_wrapper.dart';
import '../../widgets/profile/account_settings_sheet.dart';
import '../../widgets/profile/auth_view.dart';
import '../../widgets/profile/community_drawer.dart';
import '../../widgets/profile/profile_content.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _authViewKey = GlobalKey<AuthViewState>();
  final _oauth = OAuthSignInService();
  bool _localLoading = false;

  @override
  void dispose() {
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleLogin() async {
    final email = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }
    final result =
        await context.read<AuthController>().login(email, password);
    if (result['success'] != true) {
      _showError(result['message'] as String? ?? 'Sign in failed');
    }
  }

  Future<void> _handleRegister({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    final result = await context.read<AuthController>().register(
          username: username,
          email: email,
          password: password,
          fullName: fullName,
        );
    if (result['success'] != true) {
      _showError(result['message'] as String? ?? 'Registration failed');
    }
  }

  Future<void> _handleSignInWithGoogle({bool loginOnly = false}) async {
    if (Firebase.apps.isEmpty) {
      _showError('Firebase is not configured. Run flutterfire configure.');
      return;
    }
    setState(() => _localLoading = true);
    try {
      final idToken = await _oauth.signInWithGoogle();
      if (idToken == null) return;
      final credential = await _oauth.firebaseSignInWithGoogle(idToken);
      final firebaseToken = await credential.user?.getIdToken();
      if (firebaseToken == null) {
        _showError('Google sign-in failed (no token).');
        return;
      }
      final result =
          await context.read<AuthController>().exchangeFirebaseToken(firebaseToken);
      if (result['success'] != true) {
        final message = result['message'] as String? ?? 'Google sign-in failed';
        if (loginOnly && message.contains('not registered')) {
          _authViewKey.currentState?.switchToSignUpTab();
        }
        _showError(message);
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _localLoading = false);
    }
  }

  Future<void> _handleSignInWithApple({bool loginOnly = false}) async {
    if (Firebase.apps.isEmpty) {
      _showError('Firebase is not configured. Run flutterfire configure.');
      return;
    }
    setState(() => _localLoading = true);
    try {
      final apple = await _oauth.signInWithApple();
      if (apple?.idToken == null) return;
      final credential = await _oauth.firebaseSignInWithApple(
        idToken: apple!.idToken!,
        rawNonce: apple.rawNonce,
      );
      final firebaseToken = await credential.user?.getIdToken();
      if (firebaseToken == null) {
        _showError('Apple sign-in failed (no token).');
        return;
      }
      final result =
          await context.read<AuthController>().exchangeFirebaseToken(firebaseToken);
      if (result['success'] != true) {
        final message = result['message'] as String? ?? 'Apple sign-in failed';
        if (loginOnly && message.contains('not registered')) {
          _authViewKey.currentState?.switchToSignUpTab();
        }
        _showError(message);
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _localLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _loginUsernameController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email first');
      return;
    }
    final result = await context
        .read<AuthController>()
        .authService
        .sendPasswordResetEmail(email);
    _showError(
      result['success'] == true
          ? (result['message'] as String? ?? 'Reset email sent')
          : (result['message'] as String? ?? 'Reset failed'),
    );
  }

  Future<void> _handleLogout() async {
    await context.read<AuthController>().logout();
  }

  void _showSettings(Profile currentUser) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableSheetWrapper(
        childBuilder: (scrollController) => AccountSettingsSheet(
          currentUser: currentUser,
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _showCommunity() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableSheetWrapper(
        childBuilder: (scrollController) => CommunityDrawer(
          scrollController: scrollController,
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge;
    Widget button({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return Expanded(
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: scheme.primary),
          label: Text(label, style: style?.copyWith(color: scheme.primary)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    return Row(
      children: [
        button(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onPressed: () {
            final user = context.read<AuthController>().currentUser;
            if (user != null) _showSettings(user);
          },
        ),
        button(
          icon: Icons.people_outline,
          label: 'Community',
          onPressed: _showCommunity,
        ),
        button(
          icon: Icons.logout,
          label: 'Logout',
          onPressed: _handleLogout,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!auth.isLoggedIn) {
          return AuthView(
            key: _authViewKey,
            usernameController: _loginUsernameController,
            passwordController: _loginPasswordController,
            isLoading: auth.isLoading || _localLoading,
            onLogin: _handleLogin,
            onForgotPassword: _handleForgotPassword,
            onSignInWithGoogle: _handleSignInWithGoogle,
            onSignInWithApple: _handleSignInWithApple,
            onRegister: _handleRegister,
            onShowError: _showError,
          );
        }

        final profile = auth.currentUser!;
        return RefreshIndicator(
          onRefresh: auth.refreshProfile,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Profile', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _buildActionRow(context),
              const SizedBox(height: 12),
              ProfileContent(profile: profile),
            ],
          ),
        );
      },
    );
  }
}
