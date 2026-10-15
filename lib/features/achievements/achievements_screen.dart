import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'achievement_model.dart';
import 'achievements_controller.dart';

/// Grid of every achievement in the catalog — locked tiles are
/// greyed with the unlock-condition hint, unlocked tiles are gold
/// with the unlock date.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(achievementsControllerProvider);
    final total = AchievementCatalog.all.length;
    final unlockedCount = unlocked.length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(
              unlockedCount: unlockedCount,
              totalCount: total,
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.lg,
                  crossAxisSpacing: AppSpacing.lg,
                  childAspectRatio: 0.78,
                ),
                itemCount: AchievementCatalog.all.length,
                itemBuilder: (context, index) {
                  final def = AchievementCatalog.all[index];
                  final unlockAt = unlocked[def.id];
                  return _AchievementTile(
                    definition: def,
                    unlockedAt: unlockAt,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                'Keep playing to unlock every badge. New achievements '
                'are added as we ship features.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.unlockedCount,
    required this.totalCount,
  });

  final int unlockedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalCount == 0 ? 0.0 : unlockedCount / totalCount;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Your Achievements',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$unlockedCount of $totalCount unlocked',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({
    required this.definition,
    required this.unlockedAt,
  });

  final AchievementDefinition definition;
  final DateTime? unlockedAt;

  bool get _isUnlocked => unlockedAt != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final surface = AppColors.surface(brightness);

    final unlockedBg = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.dailyGold, AppColors.accent],
    );
    final lockedBg = surface;
    final iconColor =
        _isUnlocked ? Colors.white : AppColors.textSecondary(brightness);
    final titleColor =
        _isUnlocked ? Colors.white : AppColors.textPrimary(brightness);
    final hintColor = _isUnlocked
        ? Colors.white.withValues(alpha: 0.95)
        : AppColors.textSecondary(brightness);

    return Container(
      decoration: BoxDecoration(
        gradient: _isUnlocked ? unlockedBg : null,
        color: _isUnlocked ? null : lockedBg,
        borderRadius: BorderRadius.circular(20),
        border: _isUnlocked
            ? null
            : Border.all(
                color: AppColors.textSecondary(brightness)
                    .withValues(alpha: 0.25),
              ),
        boxShadow: _isUnlocked
            ? [
                BoxShadow(
                  color: AppColors.dailyGold.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isUnlocked
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.textSecondary(brightness)
                          .withValues(alpha: 0.12),
                ),
                child: Icon(
                  definition.icon,
                  size: 36,
                  color: iconColor,
                ),
              ),
              if (!_isUnlocked)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.surface(brightness),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: AppColors.textSecondary(brightness),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            definition.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: titleColor,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _isUnlocked
                ? 'Unlocked ${_formatDate(unlockedAt!)}'
                : definition.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hintColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
