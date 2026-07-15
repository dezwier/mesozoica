import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';

class AuthView extends StatefulWidget {
  const AuthView({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
    this.onForgotPassword,
    this.onSignInWithGoogle,
    this.onSignInWithApple,
    this.onRegister,
    this.onShowError,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback? onForgotPassword;
  final Future<void> Function({bool loginOnly})? onSignInWithGoogle;
  final Future<void> Function({bool loginOnly})? onSignInWithApple;
  final Future<void> Function({
    required String username,
    required String email,
    required String password,
    String? fullName,
  })? onRegister;
  final void Function(String message)? onShowError;

  @override
  State<AuthView> createState() => AuthViewState();
}

class AuthViewState extends State<AuthView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerFullNameController = TextEditingController();

  void switchToSignUpTab() {
    _tabController.animateTo(1);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerFullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Sign in'),
              Tab(text: 'Sign up'),
            ],
          ),
          const SizedBox(height: 16),
          if (AppConfig.showDebugTestAccount) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: widget.isLoading ? null : _fillDebugTestAccount,
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: const Text('Fill test account'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSignIn(context, scheme),
                _buildSignUp(context, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignIn(BuildContext context, ColorScheme scheme) {
    return ListView(
      children: [
        TextField(
          controller: widget.usernameController,
          decoration: const InputDecoration(labelText: 'Email or username'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.passwordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onForgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.isLoading ? null : widget.onLogin,
          child: widget.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
        const SizedBox(height: 16),
        _socialButtons(loginOnly: true),
      ],
    );
  }

  Widget _buildSignUp(BuildContext context, ColorScheme scheme) {
    return ListView(
      children: [
        TextField(
          controller: _registerFullNameController,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerUsernameController,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerEmailController,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _registerPasswordController,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.isLoading ? null : _handleRegister,
          child: widget.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
        const SizedBox(height: 16),
        _socialButtons(loginOnly: false),
      ],
    );
  }

  Widget _socialButtons({required bool loginOnly}) {
    return Column(
      children: [
        if (!kIsWeb && widget.onSignInWithGoogle != null)
          OutlinedButton.icon(
            onPressed: widget.isLoading
                ? null
                : () => widget.onSignInWithGoogle!(loginOnly: loginOnly),
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
        if (!kIsWeb && widget.onSignInWithApple != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.isLoading
                ? null
                : () => widget.onSignInWithApple!(loginOnly: loginOnly),
            icon: const Icon(Icons.apple),
            label: const Text('Continue with Apple'),
          ),
        ],
      ],
    );
  }

  void _fillDebugTestAccount() {
    if (_tabController.index == 0) {
      widget.usernameController.text = AppConfig.debugTestEmail;
      widget.passwordController.text = AppConfig.debugTestPassword;
      return;
    }
    _registerUsernameController.text = AppConfig.debugTestUsername;
    _registerEmailController.text = AppConfig.debugTestEmail;
    _registerPasswordController.text = AppConfig.debugTestPassword;
    _registerFullNameController.text = AppConfig.debugTestFullName;
  }

  Future<void> _handleRegister() async {
    final username = _registerUsernameController.text.trim();
    final email = _registerEmailController.text.trim();
    final password = _registerPasswordController.text;
    final fullName = _registerFullNameController.text.trim();
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      widget.onShowError?.call('Please fill in all required fields.');
      return;
    }
    await widget.onRegister?.call(
      username: username,
      email: email,
      password: password,
      fullName: fullName.isEmpty ? null : fullName,
    );
  }
}
