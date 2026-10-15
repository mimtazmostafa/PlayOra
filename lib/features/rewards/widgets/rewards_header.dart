import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../streak/streak_controller.dart';
import '../rewards_controller.dart';
import '../rewards_model.dart';

/// App-bar chip that shows the player's coins and level. Tapping it
/// deep-links into the rewards tab.
///
/// Hidden on very small screens via [compact] mode (coins-only).
class RewardsHeader extends ConsumerWidget {
  const RewardsHeader({
    super.key,
    this.onTap,
    this.compact = false,
  });

  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(rewardsControllerProvider);
    final streak = ref.watch(streakControllerProvider);
    final curve = const RewardsCurve();
    final level = curve.levelFor(snapshot.xp);
    final progress = curve.progressFor(snapshot.xp, level);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StreakChip(count: streak.count),
            const SizedBox(width: AppSpacing.sm),
            _CoinChip(count: snapshot.coins),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.sm),
              _LevelChip(
                level: level,
                progress: progress,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStreak = count > 0;
    // Raw streak orange only scores ~3.5:1 on the tinted chip in light
    // mode — switch to a darker shade so the number stays legible.
    final fg = hasStreak
        ? (theme.brightness == Brightness.dark
            ? AppColors.streak
            : AppColors.streakInk)
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.streak.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Raw gold accent only scores ~1.9:1 on white in light mode —
    // switch to a darker shade so the coin count stays legible.
    final fg = theme.brightness == Brightness.dark
        ? AppColors.accent
        : AppColors.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, required this.progress});

  final int level;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Brand purple passes AA on white but the tinted chip drops below
    // 4.5:1; use the darker shade in light mode for the chip foreground.
    final fg = theme.brightness == Brightness.dark
        ? AppColors.primary
        : AppColors.primaryInk;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_moon_rounded,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            'Lv $level',
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress > 0 && progress < 1) ...[
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: 32,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}