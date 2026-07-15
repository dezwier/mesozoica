import 'package:flutter/material.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
    this.onForgotPassword,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback? onForgotPassword;

  @override
  Widget build(BuildContext context) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: usernameController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email or username',
            hintText: 'Enter your email or username',
            border: outlineBorder,
            enabledBorder: outlineBorder,
            focusedBorder: focusedBorder,
            filled: true,
            fillColor: scheme.surface,
            prefixIcon: Icon(
              Icons.person_outline,
              color: scheme.primary,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            border: outlineBorder,
            enabledBorder: outlineBorder,
            focusedBorder: focusedBorder,
            filled: true,
            fillColor: scheme.surface,
            prefixIcon: Icon(
              Icons.lock_outline,
              color: scheme.primary,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          obscureText: true,
          enabled: !isLoading,
          style: Theme.of(context).textTheme.bodyLarge,
          onSubmitted: (_) => onLogin(),
        ),
        if (onForgotPassword != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : onForgotPassword,
              child: const Text('Forgot password?'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: ElevatedButton(
            onPressed: isLoading ? null : onLogin,
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
                    'Sign in',
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
