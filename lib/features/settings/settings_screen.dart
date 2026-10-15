// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/generated/app_localizations.dart';
import 'settings_controller.dart';

/// Settings screen — the single surface for every persisted user
/// preference.
///
/// Sections (top-to-bottom):
///   1. Appearance  — Theme mode (System / Light / Dark) wired to
///                    [SettingsController].
///   2. Notifications — toggles for daily-challenge + streak reminders
///                      (no push wiring yet — those flags will be read
///                      by the Phase 6 notification layer).
///   3. Data & Storage — Downloads placeholder ("0 MB used").
///   4. About       — version row + Privacy Policy / Terms links.
///   5. Subscription — "Manage Subscription" deep-link to the
///                     placeholder screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          children: [
            _SectionHeader(text: l10n.settingsAppearanceSection),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  _ThemeModeTile(
                    label: l10n.settingsAppearanceThemeModeSystem,
                    value: ThemeMode.system,
                    groupValue: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const Divider(height: 1),
                  _ThemeModeTile(
                    label: l10n.settingsAppearanceThemeModeLight,
                    value: ThemeMode.light,
                    groupValue: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const Divider(height: 1),
                  _ThemeModeTile(
                    label: l10n.settingsAppearanceThemeModeDark,
                    value: ThemeMode.dark,
                    groupValue: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            _SectionHeader(text: l10n.settingsNotificationsSection),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(l10n.settingsNotificationsDailyChallenge),
                    subtitle: Text(
                      l10n.settingsNotificationsDailyChallengeSubtitle,
                    ),
                    value: settings.dailyReminderOn,
                    onChanged: notifier.setDailyReminderOn,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(l10n.settingsNotificationsStreak),
                    subtitle: Text(
                      l10n.settingsNotificationsStreakSubtitle,
                    ),
                    value: settings.streakReminderOn,
                    onChanged: notifier.setStreakReminderOn,
                  ),
                ],
              ),
            ),
            AppSpacing.gapXl,
            _SectionHeader(text: l10n.settingsDataStorageSection),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.download_rounded),
                title: Text(l10n.settingsDataStorageDownloads),
                trailing: Text(
                  l10n.settingsDataStorageDownloadsValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary(theme.brightness),
                  ),
                ),
              ),
            ),
            AppSpacing.gapXl,
            _SectionHeader(text: l10n.settingsAboutSection),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.settingsAboutSection),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary(theme.brightness),
                ),
                onTap: () => context.push(AppRoutes.about),
              ),
            ),
            AppSpacing.gapXxl,
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.sm,
        top: AppSpacing.xs,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary(theme.brightness),
          letterSpacing: 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final ThemeMode value;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode>(
      title: Text(label),
      value: value,
      groupValue: groupValue,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}
