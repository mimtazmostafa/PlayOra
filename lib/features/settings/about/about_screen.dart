import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';

/// About surface reachable from Settings.
///
/// Surfaces the app version (read from the package_info equivalent
/// shipped with pubspec: 1.0.0+1) and links to the placeholder
/// Privacy Policy and Terms of Service screens. The product goal is
/// just to give users a destination for those rows before the legal
/// copy lands.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Static version constant — mirrors the `version:` field in
  /// pubspec.yaml. Phase 8 swaps this for a `package_info_plus` read.
  static const String appVersion = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAboutSection)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          children: [
            _AboutTile(
              label: l10n.settingsAboutVersion,
              trailing: Text(
                appVersion,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(theme.brightness),
                ),
              ),
            ),
            const Divider(height: 1),
            _AboutTile(
              label: l10n.settingsAboutPrivacyPolicy,
              showChevron: true,
              onTap: () => context.push(AppRoutes.privacyPolicy),
            ),
            const Divider(height: 1),
            _AboutTile(
              label: l10n.settingsAboutTerms,
              showChevron: true,
              onTap: () => context.push(AppRoutes.terms),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.label,
    this.trailing,
    this.showChevron = false,
    this.onTap,
  });

  final String label;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge,
      ),
      trailing: trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary(theme.brightness),
                )
              : null),
      onTap: onTap,
    );
  }
}