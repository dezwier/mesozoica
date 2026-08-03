import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/theme_controller.dart';
import '../../services/location_service.dart';
import 'settings_form_styles.dart';

class SettingsAppTab extends StatelessWidget {
  const SettingsAppTab({super.key});

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
                    child: Text(option.label, style: theme.textTheme.bodyMedium),
                  ),
              ],
              onSelected: (value) {
                if (value != null) themeController.setMapBasemapTheme(value);
              },
            ),
          ),
          const SizedBox(height: 24),
          SettingsFormStyles.settingsRow(
            context: context,
            label: 'Explore in background',
            description:
                'Keep site discovery, walk XP, and site exploration running '
                'while the phone is locked. Uses more battery. Requires Always '
                'location permission.',
            controlWidth: 56,
            control: Switch.adaptive(
              value: locationService.isBackgroundExploring,
              onChanged: (value) async {
                final ok =
                    await locationService.setBackgroundExploring(value);
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
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}
