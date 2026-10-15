import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Lightweight static-text screen used as a placeholder for the
/// Privacy Policy and Terms of Service documents until the legal team
/// publishes the final copy.
///
/// Drives the body from [AppLocalizations] so the page is ready for
/// full translations in Phase 6.
class StaticLegalScreen extends StatelessWidget {
  const StaticLegalScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall,
              ),
              AppSpacing.gapMd,
              Text(
                l10n.aboutPlaceholderBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(theme.brightness),
                  height: 1.5,
                ),
              ),
              AppSpacing.gapMd,
              Text(
                l10n.aboutPlaceholderBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(theme.brightness),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}