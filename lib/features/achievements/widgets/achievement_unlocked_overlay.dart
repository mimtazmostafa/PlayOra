import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../achievement_model.dart';
import '../achievements_controller.dart';

/// Listens on [achievementUnlockedStreamProvider] and shows a gold
/// "Achievement Unlocked!" burst for every newly unlocked achievement.
///
/// Mounted once at the app root via `MaterialApp.builder`. Distinct
/// from the level-up overlay (purple) and the daily-challenge overlay
/// (gold-elephant) so the three celebrations don't feel like the
/// same animation.
class AchievementUnlockedOverlay extends ConsumerStatefulWidget {
  const AchievementUnlockedOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AchievementUnlockedOverlay> createState() =>
      _AchievementUnlockedOverlayState();
}

class _AchievementUnlockedOverlayState
    extends ConsumerState<AchievementUnlockedOverlay>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  final List<AchievementUnlock> _queue = <AchievementUnlock>[];
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    _entry?.remove();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _entry?.remove();
      _entry = null;
      _pumpNext();
    }
  }

  void _pumpNext() {
    if (_queue.isEmpty) return;
    final next = _queue.removeAt(0);
    _show(next);
  }

  void _show(AchievementUnlock unlock) {
    _entry?.remove();
    final entry = OverlayEntry(
      builder: (_) => _UnlockBurst(unlock: unlock),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _controller
      ..stop()
      ..forward(from: 0);
  }

  void _enqueue(List<AchievementUnlock> unlocks) {
    if (unlocks.isEmpty) return;
    _queue.addAll(unlocks);
    // If no burst is on screen, kick the queue.
    if (_entry == null) _pumpNext();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<AchievementUnlock>>>(
      achievementUnlockedStreamProvider,
      (previous, next) {
        next.whenData(_enqueue);
      },
    );
    return widget.child;
  }
}

class _UnlockBurst extends StatelessWidget {
  const _UnlockBurst({required this.unlock});

  final AchievementUnlock unlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, t, _) {
              return Opacity(
                opacity: (1 - (1 - t).abs()).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + (t * 0.6),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.dailyGold,
                          AppColors.accent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.dailyGold.withValues(alpha: 0.55),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          child: Icon(
                            unlock.definition.icon,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Achievement Unlocked!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          unlock.definition.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          unlock.definition.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
