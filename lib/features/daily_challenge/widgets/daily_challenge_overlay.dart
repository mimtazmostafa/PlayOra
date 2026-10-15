import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../daily_challenge_controller.dart';

/// Listens on [dailyChallengeCompletedStreamProvider] and shows a
/// gold "Daily Cleared!" burst the first time the user crosses
/// today's target score. Visually distinct from the level-up
/// overlay so the two never feel like the same celebration.
class DailyChallengeOverlay extends ConsumerStatefulWidget {
  const DailyChallengeOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyChallengeOverlay> createState() =>
      _DailyChallengeOverlayState();
}

class _DailyChallengeOverlayState
    extends ConsumerState<DailyChallengeOverlay>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
    if (status == AnimationStatus.completed && _entry != null) {
      _entry!.remove();
      _entry = null;
    }
  }

  void _show(DailyChallengeWin win) {
    _entry?.remove();
    final entry = OverlayEntry(
      builder: (_) => _DailyBurst(win: win),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DailyChallengeWin>>(
      dailyChallengeCompletedStreamProvider,
      (previous, next) {
        next.whenData(_show);
      },
    );
    return widget.child;
  }
}

class _DailyBurst extends StatelessWidget {
  const _DailyBurst({required this.win});

  final DailyChallengeWin win;

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
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Daily Cleared!',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${win.score} / ${win.target} pts',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
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