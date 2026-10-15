import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../achievements/achievement_model.dart';
import '../achievements/achievements_controller.dart';
import '../rewards/rewards_controller.dart';
import '../rewards/rewards_model.dart';
import '../rewards/widgets/rewards_header.dart';

/// Profile tab — player identity, lifetime rewards, and a deep-link
/// to the rewards screen. Game-library and account settings are
/// roadmap items for later phases.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(rewardsControllerProvider);
    const curve = RewardsCurve();
    final level = curve.levelFor(snapshot.xp);
    final progress = curve.progressFor(snapshot.xp, level);
    final unlockedCount =
        ref.watch(achievementsControllerProvider).length;
    final totalAchievements = AchievementCatalog.all.length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          RewardsHeader(
            compact: true,
            onTap: () => context.go(AppRoutes.rewards),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.primary,
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Player',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Level $level • ${snapshot.coins} coins',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.15),
                  // Use the darker purple for the filled bar so it clears
                  // AA against the lightly-tinted track in light mode.
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.brightness == Brightness.dark
                        ? AppColors.primary
                        : AppColors.primaryInk,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${snapshot.xp} XP total',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _MenuLink(
                icon: Icons.emoji_events_rounded,
                // Gold trophy on white drops to 1.9:1 — swap to the
                // darker accent shade so the icon stays legible.
                iconColor: theme.brightness == Brightness.dark
                    ? AppColors.dailyGold
                    : AppColors.accentInk,
                title: 'Achievements',
                subtitle:
                    '$unlockedCount of $totalAchievements unlocked',
                onTap: () => context.go(AppRoutes.achievements),
              ),
              const SizedBox(height: AppSpacing.sm),
              _MenuLink(
                icon: Icons.settings_rounded,
                iconColor: theme.brightness == Brightness.dark
                    ? AppColors.primary
                    : AppColors.primaryInk,
                title: 'Settings',
                subtitle: 'Theme, language, and more',
                onTap: () => context.go(AppRoutes.settings),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Your library and account settings arrive in a later '
                'phase. Keep playing to climb the ranks!',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.textTheme.bodyMedium?.color
                      ?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLink extends StatelessWidget {
  const _MenuLink({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface(theme.brightness),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.textSecondary(theme.brightness)
                  .withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(theme.brightness),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary(theme.brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
