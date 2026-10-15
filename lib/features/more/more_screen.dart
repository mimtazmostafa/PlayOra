// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/local/user_stats_dao.dart';
import '../auth/auth_controller.dart';
import '../games/widgets/game_artwork.dart';
import '../profile/profile_controller.dart';
import '../settings/settings_controller.dart';
import '../streak/streak_controller.dart';

/// The "More" tab — the redesigned settings surface.
///
/// Sections (top → bottom), matching the reference image:
///
///   1. **Header** — "More" title + subtitle "Make PlayNest yours".
///   2. **Account card** — large game-art tile + display-name + a tiny
///      "Lifetime • N games" stat line so the screen doesn't open on
///      an empty surface even with no favorites.
///   3. **Preferences** — Language / Sound / Vibration / Them
/// e. Every
///      row uses the same `_MoreLink` shape with a chevron so the
///      screen feels like one cohesive list rather than a stack of
///      widgets. Theme is a selectable segmented control in place of a
///      chevron when the row is tapped.
///   4. **About PlayNest** — version + "Made with ❤ in Bangladesh"
///      footer.
///
/// Multi-select preferences (Sound / Vibration) live on the persisted
/// [SettingsController]. The Profile deep-link is preserved so users
/// can still edit their display name.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _isUnsubscribing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);
    final summary = ref.watch(userStatsSummaryProvider);
    final streak = ref.watch(streakControllerProvider);
    final name = ref.watch(profileControllerProvider);
    final session = ref.watch(subscriptionControllerProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _Header(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _AccountCard(
                name: name,
                totalGamesPlayed: summary.totalGamesPlayed,
                streak: streak.count,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Subscription section — mobile + carrier chips, plus the
            // two destructive actions: Logout (local-only) and
            // Unsubscribe (carrier-cancelling).
            const _SectionHeader(text: 'Subscription'),
            _SubscriptionCard(session: session),
            _MoreLink(
              icon: Icons.logout_rounded,
              iconColor: AppColors.feature,
              title: 'Logout',
              subtitle: 'Sign out of this device — subscription stays active',
              onTap: _isUnsubscribing ? null : _onLogoutTap,
            ),
            _MoreLink(
              icon: Icons.no_accounts_rounded,
              iconColor: AppColors.error,
              title: 'Unsubscribe',
              subtitle: 'Cancel your PlayNest subscription via carrier',
              onTap: _isUnsubscribing ? null : _onUnsubscribeTap,
              destructive: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeader(text: 'Preferences'),
            _ToggleLink(
              icon: Icons.volume_up_rounded,
              iconColor: AppColors.play,
              title: 'Sound',
              subtitle: 'In-game sound effects',
              value: settings.soundOn,
              onChanged: notifier.setSoundOn,
            ),
            _ToggleLink(
              icon: Icons.vibration_rounded,
              iconColor: AppColors.streak,
              title: 'Vibration',
              subtitle: 'Haptic feedback while playing',
              value: settings.hapticsOn,
              onChanged: notifier.setHapticsOn,
            ),
            _ThemeLink(
              current: settings.themeMode,
              onChanged: notifier.setThemeMode,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeader(text: 'About PlayNest'),
            _MoreLink(
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.feature,
              title: 'About PlayNest',
              subtitle: 'Version • Credits • Legal',
              onTap: () => context.push(AppRoutes.about),
            ),
            _MoreLink(
              icon: Icons.edit_rounded,
              iconColor: AppColors.play,
              title: 'Edit profile',
              subtitle: 'Display name and avatar',
              onTap: () => context.push(AppRoutes.profile),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Footer(theme: theme),
          ],
        ),
      ),
    );
  }

  Future<void> _onLogoutTap() async {
    final confirmed = await _showConfirmDialog(
      title: 'Logout?',
      message:
          'You will be signed out on this device. Your subscription stays active — log back in any time with the same number.',
      confirmLabel: 'Logout',
      confirmColor: AppColors.feature,
    );
    if (!confirmed || !mounted) return;
    await ref.read(subscriptionControllerProvider.notifier).logout();
    if (!mounted) return;
    // Auth gate will pick up the session flip and route to /login.
    context.go(AppRoutes.login);
  }

  Future<void> _onUnsubscribeTap() async {
    // ── Re-entrancy guard ─────────────────────────────────────────
    // The button's `onTap` already gates on `_isUnsubscribing`, but
    // the controller-level guard below is the source of truth so
    // a stale widget tree (e.g. a queued tap before the rebuild
    // lands) can't fire two unsubscribes in parallel. The previous
    // build did not have this guard and could leave the user
    // without a session AND without a history record (one race
    // ordering) — the symptom was "Unsubscribe does not reliably
    // update UI/session after a successful S1000/UNREGISTERED
    // response".
    if (_isUnsubscribing) return;
    final session = ref.read(subscriptionControllerProvider);
    final savedNumber = session.mobile;

    // Spec: confirm dialog before calling unsubscribe.
    final confirmed = await _showConfirmDialog(
      title: 'Unsubscribe from PlayNest?',
      message:
          'This cancels your PlayNest subscription with the carrier. '
          'You will lose access to all 50+ games on this number. '
          'You will receive an SMS confirmation from your operator '
          'shortly after.',
      confirmLabel: 'Unsubscribe',
      confirmColor: AppColors.error,
    );
    if (!confirmed || !mounted) return;

    // Defensive: no saved number on file means there's nothing to
    // unsubscribe on the carrier side. Treat as a local-only
    // clear so the user isn't stuck behind an unsubscribable
    // session.
    if (savedNumber.isEmpty) {
      await ref.read(subscriptionControllerProvider.notifier).logout();
      if (!mounted) return;
      context.go(AppRoutes.login);
      return;
    }

    setState(() => _isUnsubscribing = true);
    try {
      final api = ref.read(bdAppsApiProvider);
      final result = await api.unsubscribe(mobile: savedNumber);
      if (!mounted) return;

      if (result.isNotSubscribed) {
        // Spec: S1000 + UNREGISTERED → clear the saved number
        // and session, show "You have been unsubscribed", go to
        // Login/Welcome. (BDApps sends the unsubscribe-SMS itself;
        // the app does nothing else.)
        //
        // CRITICAL ORDERING FIX (was the bug behind the unreliable
        // Unsubscribe button):
        //   1. `forgetMobile(savedNumber)` FIRST — drops the number
        //      from the logout-safe history so a later Login
        //      round-trip with the same number correctly reports
        //      "not subscribed" instead of masking the unsubscribed
        //      state behind a stale history record.
        //   2. THEN `logout()` — clears the active session.
        //
        // The previous build called `logout()` first; the router's
        // auth gate (`!isSubscribed && !atAuth` → `/subscribe`)
        // fires synchronously on the state change and unmounts
        // `_MoreScreenState`. By the time we reached
        // `forgetMobile(savedNumber)`, `mounted` was already false
        // and the call was skipped via the early-return guards.
        // The history record survived → the user could log back in
        // with the same number and the Login flow would still
        // mis-report REGISTERED.
        //
        // We now run both writes against the repository BEFORE
        // the router redirect kicks in: `forgetMobile` first so the
        // history drop is the first committed change, then
        // `logout` which is the trigger for the redirect. Both
        // awaits must complete before the dialog opens so the user
        // can't back out and leave the state half-cleaned.
        await ref
            .read(subscriptionControllerProvider.notifier)
            .forgetMobile(savedNumber);
        if (!mounted) return;
        await ref.read(subscriptionControllerProvider.notifier).logout();
        if (!mounted) return;
        await _showInfoDialog(
          title: 'You have been unsubscribed',
          message:
              'Your PlayNest subscription on this number has been '
              'cancelled. You will receive an SMS confirmation from '
              'your carrier shortly.\n\nYou can subscribe again any '
              'time with the same number.',
        );
        // No `context.go(AppRoutes.login)` here — by the time
        // the dialog closes the router has already redirected the
        // user to `/subscribe` (the auth gate's destination for
        // any unsubscribed user), and `/subscribe` provides the
        // same Subscribe CTA they'd land on from `/login`'s error
        // panel. Issuing a second `context.go` was a leftover from
        // the previous build that occasionally raced the dialog
        // dismissal and pushed the user back to `/login` (which
        // then bounced them to `/subscribe` anyway). Single
        // source of truth = the router.
        return;
      }

      // Spec: error → keep the user logged in (the carrier still
      // considers them subscribed), show the upstream `message`
      // verbatim, allow Retry. We do NOT clear the session.
      _showSnack(
        'Could not unsubscribe. ${result.errorMessage ?? 'Please try again.'} '
        'Your subscription is still active.',
        isError: true,
      );
    } finally {
      // CRITICAL: clearing `_isUnsubscribing` in `finally` means a
      // thrown future (e.g. a Hive closed mid-write, an API
      // timeout during the dialog open) cannot leave the button
      // stuck in its loading state. This mirrors the same
      // `finally` discipline we apply to the Login screen's
      // Verify & Continue button.
      if (mounted) setState(() => _isUnsubscribing = false);
    }
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: Theme.of(dialogCtx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          content: Text(message),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.mint,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: Theme.of(dialogCtx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: confirmColor,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

/// Header label + subtitle.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'More',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Make PlayNest yours',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.totalGamesPlayed,
    required this.streak,
  });

  final String name;
  final int totalGamesPlayed;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface(theme.brightness),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.35 : 0.06,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          GameArtwork(
            id: 'block-puzzle',
            accent: AppColors.play,
            size: 64,
            padding: 10,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lifetime • $totalGamesPlayed games',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 14,
                      color: streak > 0 ? AppColors.streak : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$streak day streak',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: streak > 0 ? AppColors.streak : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w900,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: AppColors.surface(brightness),
        borderRadius: BorderRadius.circular(24),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: brightness == Brightness.dark ? 0.25 : 0.04,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: destructive
                      ? AppColors.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.session});

  final SubscriptionState session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = session.mobile;
    final hasMobile = mobile.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface(theme.brightness),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.mint.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.25 : 0.04,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.verified_rounded,
                color: AppColors.mint,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Subscribed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasMobile
                        ? 'Active on $mobile'
                        : 'Active subscription',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleLink extends StatelessWidget {
  const _ToggleLink({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface(brightness),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: brightness == Brightness.dark ? 0.25 : 0.04,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              activeThumbColor: AppColors.play,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeLink extends StatelessWidget {
  const _ThemeLink({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface(brightness),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: brightness == Brightness.dark ? 0.25 : 0.04,
              ),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.feature.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.color_lens_rounded,
                color: AppColors.feature,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Theme',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.auto_awesome_rounded, size: 14),
                        label: Text('Auto'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_rounded, size: 14),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_rounded, size: 14),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: <ThemeMode>{current},
                    onSelectionChanged: (set) {
                      HapticFeedback.selectionClick();
                      onChanged(set.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'PlayNest v1.0.0',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Made with ❤ in Bangladesh',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
