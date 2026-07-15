import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import 'login_form.dart';

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

class _SocialButtonData {
  const _SocialButtonData({
    required this.label,
    required this.logoUrl,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.onPressed,
  });

  final String label;
  final String logoUrl;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final Future<void> Function() onPressed;
}

class _SocialSignInButton extends StatelessWidget {
  const _SocialSignInButton({
    required this.data,
    required this.isLoading,
  });

  final _SocialButtonData data;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : data.onPressed,
        icon: _NetworkLogo(
          logoUrl: data.logoUrl,
          fallbackIcon: data.fallbackIcon,
          fallbackColor: data.fallbackColor,
          size: 18,
        ),
        label: Text(data.label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _NetworkLogo extends StatelessWidget {
  const _NetworkLogo({
    required this.logoUrl,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.size,
  });

  final String logoUrl;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      logoUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        fallbackIcon,
        size: size,
        color: fallbackColor,
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: SizedBox(
              width: size * 0.7,
              height: size * 0.7,
              child: const CircularProgressIndicator(strokeWidth: 1.8),
            ),
          ),
        );
      },
    );
  }
}

class _SignInTab extends StatelessWidget {
  const _SignInTab({
    required this.usernameController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
    this.onForgotPassword,
    this.onSignInWithGoogle,
    this.onSignInWithApple,
    required this.onSwitchToSignUp,
    this.onFillDebugTestAccount,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback? onForgotPassword;
  final Future<void> Function({bool loginOnly})? onSignInWithGoogle;
  final Future<void> Function({bool loginOnly})? onSignInWithApple;
  final VoidCallback onSwitchToSignUp;
  final VoidCallback? onFillDebugTestAccount;

  @override
  Widget build(BuildContext context) {
    final signInButtons = _buildSocialButtons(loginOnly: true);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: LoginForm(
                usernameController: usernameController,
                passwordController: passwordController,
                isLoading: isLoading,
                onLogin: onLogin,
                onForgotPassword: onForgotPassword,
              ),
            ),
          ),
          if (signInButtons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OrContinueWithDivider(),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var index = 0; index < signInButtons.length; index++) ...[
                  Expanded(child: signInButtons[index]),
                  if (index != signInButtons.length - 1)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSwitchToSignUp,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                "Don't have an account? Sign up",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (onFillDebugTestAccount != null) ...[
            const SizedBox(height: 16),
            Text(
              'Debug',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onFillDebugTestAccount,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('Fill test account'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _buildSocialButtons({required bool loginOnly}) {
    if (kIsWeb) return const [];

    return [
      if (onSignInWithGoogle != null)
        _SocialSignInButton(
          data: _SocialButtonData(
            label: 'Google',
            logoUrl: 'https://img.icons8.com/color/96/google-logo.png',
            fallbackIcon: Icons.g_mobiledata,
            fallbackColor: const Color(0xFF4285F4),
            onPressed: () async =>
                await onSignInWithGoogle!(loginOnly: loginOnly),
          ),
          isLoading: isLoading,
        ),
      if (onSignInWithApple != null)
        _SocialSignInButton(
          data: _SocialButtonData(
            label: 'Apple',
            logoUrl: 'https://img.icons8.com/fluency/96/mac-os.png',
            fallbackIcon: Icons.apple,
            fallbackColor: const Color(0xFF8E8E93),
            onPressed: () async =>
                await onSignInWithApple!(loginOnly: loginOnly),
          ),
          isLoading: isLoading,
        ),
    ];
  }
}

class _SignUpTab extends StatelessWidget {
  const _SignUpTab({
    required this.registerUsernameController,
    required this.registerEmailController,
    required this.registerPasswordController,
    required this.registerFullNameController,
    required this.isLoading,
    required this.onRegister,
    this.onSignInWithGoogle,
    this.onSignInWithApple,
    required this.onSwitchToSignIn,
    this.onFillDebugTestAccount,
  });

  final TextEditingController registerUsernameController;
  final TextEditingController registerEmailController;
  final TextEditingController registerPasswordController;
  final TextEditingController registerFullNameController;
  final bool isLoading;
  final Future<void> Function() onRegister;
  final Future<void> Function({bool loginOnly})? onSignInWithGoogle;
  final Future<void> Function({bool loginOnly})? onSignInWithApple;
  final VoidCallback onSwitchToSignIn;
  final VoidCallback? onFillDebugTestAccount;

  @override
  Widget build(BuildContext context) {
    final signUpButtons = _buildSocialButtons(loginOnly: false);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          Text(
            'Create an account',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _buildRegisterForm(context),
            ),
          ),
          if (signUpButtons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OrContinueWithDivider(),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var index = 0; index < signUpButtons.length; index++) ...[
                  Expanded(child: signUpButtons[index]),
                  if (index != signUpButtons.length - 1)
                    const SizedBox(width: 10),
                ],
              ],
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSwitchToSignIn,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Already have an account? Sign in',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          if (onFillDebugTestAccount != null) ...[
            const SizedBox(height: 16),
            Text(
              'Debug',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onFillDebugTestAccount,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('Fill test account'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _buildSocialButtons({required bool loginOnly}) {
    if (kIsWeb) return const [];

    return [
      if (onSignInWithGoogle != null)
        _SocialSignInButton(
          data: _SocialButtonData(
            label: 'Google',
            logoUrl: 'https://img.icons8.com/color/96/google-logo.png',
            fallbackIcon: Icons.g_mobiledata,
            fallbackColor: const Color(0xFF4285F4),
            onPressed: () async =>
                await onSignInWithGoogle!(loginOnly: loginOnly),
          ),
          isLoading: isLoading,
        ),
      if (onSignInWithApple != null)
        _SocialSignInButton(
          data: _SocialButtonData(
            label: 'Apple',
            logoUrl: 'https://img.icons8.com/fluency/96/mac-os.png',
            fallbackIcon: Icons.apple,
            fallbackColor: const Color(0xFF8E8E93),
            onPressed: () async =>
                await onSignInWithApple!(loginOnly: loginOnly),
          ),
          isLoading: isLoading,
        ),
    ];
  }

  Widget _buildRegisterForm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final softBorderSide = BorderSide(
      color: scheme.outline.withValues(alpha: isLight ? 0.3 : 0.5),
    );
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: softBorderSide,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );

    InputDecoration fieldDecoration({
      required String labelText,
      required String hintText,
      required IconData prefixIcon,
    }) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: focusedBorder,
        filled: true,
        fillColor: scheme.surface,
        prefixIcon: Icon(prefixIcon, color: scheme.primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: registerFullNameController,
          decoration: fieldDecoration(
            labelText: 'Full name',
            hintText: 'Enter your full name',
            prefixIcon: Icons.badge_outlined,
          ),
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: registerUsernameController,
          decoration: fieldDecoration(
            labelText: 'Username',
            hintText: 'Choose a username',
            prefixIcon: Icons.person_outline,
          ),
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: registerEmailController,
          decoration: fieldDecoration(
            labelText: 'Email',
            hintText: 'Enter your email',
            prefixIcon: Icons.email_outlined,
          ),
          keyboardType: TextInputType.emailAddress,
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: registerPasswordController,
          decoration: fieldDecoration(
            labelText: 'Password',
            hintText: 'Create a password',
            prefixIcon: Icons.lock_outline,
          ),
          obscureText: true,
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
          onSubmitted: (_) => onRegister(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: ElevatedButton(
            onPressed: isLoading ? null : onRegister,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            child: isLoading
                ? SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.onPrimary,
                      ),
                    ),
                  )
                : Text(
                    'Create account',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _OrContinueWithDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);
    return Row(
      children: [
        Expanded(child: Divider(color: outline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Or continue with',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(child: Divider(color: outline)),
      ],
    );
  }
}
