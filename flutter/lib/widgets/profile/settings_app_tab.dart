import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/theme_controller.dart';
import 'settings_form_styles.dart';

class SettingsAppTab extends StatelessWidget {
  const SettingsAppTab({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final theme = Theme.of(context);
    final themeMode = themeController.themeMode;
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
          SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
        ],
      ),
    );
  }
}
