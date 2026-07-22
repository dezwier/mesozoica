part of 'auth_view.dart';

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
