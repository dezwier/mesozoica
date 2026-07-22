import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import 'login_form.dart';

part 'auth_view_social.dart';
part 'auth_view_tabs.dart';

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

class AuthViewState extends State<AuthView> with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final focusScope = FocusScope.of(context);
        if (!focusScope.hasPrimaryFocus) {
          focusScope.unfocus();
        }
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Sign in'),
                    Tab(text: 'Sign up'),
                  ],
                  labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _SignInTab(
                        usernameController: widget.usernameController,
                        passwordController: widget.passwordController,
                        isLoading: widget.isLoading,
                        onLogin: widget.onLogin,
                        onForgotPassword: widget.onForgotPassword,
                        onSignInWithGoogle: widget.onSignInWithGoogle,
                        onSignInWithApple: widget.onSignInWithApple,
                        onSwitchToSignUp: switchToSignUpTab,
                        onFillDebugTestAccount: AppConfig.showDebugTestAccount
                            ? _fillDebugTestAccount
                            : null,
                      ),
                      _SignUpTab(
                        registerUsernameController: _registerUsernameController,
                        registerEmailController: _registerEmailController,
                        registerPasswordController: _registerPasswordController,
                        registerFullNameController: _registerFullNameController,
                        isLoading: widget.isLoading,
                        onRegister: _handleRegister,
                        onSignInWithGoogle: widget.onSignInWithGoogle,
                        onSignInWithApple: widget.onSignInWithApple,
                        onSwitchToSignIn: () => _tabController.animateTo(0),
                        onFillDebugTestAccount: AppConfig.showDebugTestAccount
                            ? _fillDebugTestAccount
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
