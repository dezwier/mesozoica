import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/theme_controller.dart';
import '../../features/legal/legal.dart';
import '../../services/location_service.dart';
import 'settings_form_styles.dart';

class SettingsAppTab extends StatelessWidget {
  const SettingsAppTab({super.key, required this.onRequestDeleteAccount});

  final VoidCallback onRequestDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final locationService = context.watch<LocationService>();
    final theme = Theme.of(context);
    final themeMode = themeController.themeMode;
    final mapBasemapTheme = themeController.mapBasemapTheme;
    final outlineBorder = SettingsFormStyles.outlineBorder(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          SettingsFormStyles.settingsRow(
            context: context,
            label: 'Background location',
            description:
                'Keep site discovery, walk XP, and site exploration running '
                'while the phone is locked. Uses more battery. Requires Always '
                'location permission.',
            controlWidth: 56,
            control: Switch.adaptive(
              value: locationService.isBackgroundExploring,
              onChanged: (value) async {
                if (value) {
                  final accepted = await _confirmBackgroundLocation(context);
                  if (!accepted || !context.mounted) return;
                }
                final ok = await locationService.setBackgroundExploring(value);
                if (!context.mounted) return;
                if (value && !ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        locationService.error ??
                            'Always location permission is required. '
                                'Enable it in system Settings.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRequestDeleteAccount,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Delete account'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SettingsFormStyles.settingsRow(
            context: context,
            label: 'Appearance',
            description: 'Choose light, dark, or match your device.',
            control: SettingsFormStyles.densePopupField<ThemeMode>(
              context: context,
              outlineBorder: outlineBorder,
              selectedChild: Text(
                switch (themeMode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  _ => 'Device',
                },
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              entries: [
                DensePopupEntry(
                  value: ThemeMode.light,
                  child: Text('Light', style: theme.textTheme.bodyMedium),
                ),
                DensePopupEntry(
                  value: ThemeMode.dark,
                  child: Text('Dark', style: theme.textTheme.bodyMedium),
                ),
                DensePopupEntry(
                  value: ThemeMode.system,
                  child: Text('Device', style: theme.textTheme.bodyMedium),
                ),
              ],
              onSelected: (value) {
                if (value != null) themeController.setThemeMode(value);
              },
            ),
          ),
          const SizedBox(height: 24),
          SettingsFormStyles.settingsRow(
            context: context,
            label: 'Map theme',
            description: 'Mapbox Standard color theme for the field map.',
            control: SettingsFormStyles.densePopupField<MapboxBasemapTheme>(
              context: context,
              outlineBorder: outlineBorder,
              selectedChild: Text(
                mapBasemapTheme.label,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              entries: [
                for (final option in MapboxBasemapTheme.values)
                  DensePopupEntry(
                    value: option,
                    child: Text(
                      option.label,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
              onSelected: (value) {
                if (value != null) themeController.setMapBasemapTheme(value);
              },
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Legal',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _legalTile(
            context,
            label: 'Privacy policy',
            assetPath: kPrivacyPolicyAsset,
          ),
          _legalTile(
            context,
            label: 'Terms and conditions',
            assetPath: kTermsAsset,
          ),
          _legalTile(
            context,
            label: 'Account deletion policy',
            assetPath: kDeleteAccountAsset,
          ),
          _legalTile(
            context,
            label: 'Delete data',
            assetPath: kDeleteDataAsset,
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}

Widget _legalTile(
  BuildContext context, {
  required String label,
  required String assetPath,
}) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        LegalDocumentScreen.open(context, title: label, assetPath: assetPath),
  );
}

Future<bool> _confirmBackgroundLocation(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Use location in the background?'),
      content: const Text(
        'Mesozoica collects your location while the app is in the '
        'background so nearby fossil sites can still be discovered, an '
        'in-range site can keep documenting, and walk XP can continue. '
        'This uses more battery. You can turn it off here at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return accepted == true;
}
