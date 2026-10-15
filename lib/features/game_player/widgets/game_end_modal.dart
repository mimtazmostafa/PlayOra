import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../achievements/achievements_controller.dart';
import '../../achievements/play_history_controller.dart';
import '../../daily_challenge/daily_challenge_controller.dart';
import '../../games/games_providers.dart';
import '../../profile/played_games_controller.dart';
import '../../rewards/rewards_controller.dart';
import '../../rewards/rewards_model.dart';
import '../../rewards/widgets/animated_count_up.dart';
import '../../streak/streak_controller.dart';

/// Post-game results modal — shared by every playable game.
///
/// Shown via [GameEndModal.show] when a [GameModule.onGameEnd] callback
/// fires. The modal runs the same 5-step award pipeline that the
/// previous [PostGameRewardsScreen] used (rewards → streak → daily
/// challenge → daily bonus → achievements) so the numbers match what
/// the player has come to expect, then renders the trophy + score +
/// count-up coin/XP chips + Play Again / Back to Home actions.
///
/// Animates in with a fade + scale spring (280ms) and an internal
/// [TweenAnimationBuilder] that staggers the trophy, score, and reward
/// rows so the result lands with a sense of weight.
class GameEndModal extends ConsumerStatefulWidget {
  const GameEndModal({
    super.key,
    required this.gameId,
    required this.score,
    this.bestScore,
  });

  final String gameId;
  final int score;

  /// Previous personal best, if the caller has it. When supplied and
  /// [score] strictly exceeds it, the modal renders a "NEW BEST!"
  /// ribbon above the score so the milestone lands with weight.
  final int? bestScore;

  /// Display formula — also asserted in a widget test.
  static int coinsForScore(int score) => score ~/ 10;

  /// Display formula — also asserted in a widget test.
  static int xpForScore(int score) => score ~/ 5;

  /// Coin bonus awarded when the user clears today's daily challenge
  /// for the first time. Scaled with the score so a tighter target
  /// still rewards generously, but capped to avoid runaway payouts.
  static int dailyBonusForScore(int score) {
    final raw = score ~/ 5;
    return raw > 100 ? 100 : raw;
  }

  /// Show as a fullscreen modal dialog over the game screen. Resolves
  /// when the modal is dismissed (Play Again pushes a fresh game route,
  /// Back to Home navigates to the bottom-nav shell, scrim tap is a
  /// no-op so the player can't accidentally lose the results).
  ///
  /// Pass [bestScore] when the host has access to the previous personal
  /// best (most call sites don't track it yet — the ribbon stays hidden
  /// rather than fabricating a value).
  static Future<void> show(
    BuildContext context, {
    required String gameId,
    required int score,
    int? bestScore,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Game Over',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim, secondary) => GameEndModal(
        gameId: gameId,
        score: score,
        bestScore: bestScore,
      ),
      transitionBuilder: (ctx, anim, secondary, child) {
        final eased = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(eased),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<GameEndModal> createState() => _GameEndModalState();
}

class _GameEndModalState extends ConsumerState<GameEndModal> {
  int _coinsEarned = 0;
  int _xpEarned = 0;
  int _dailyBonus = 0;
  bool _awarded = false;

  /// True when the caller supplied a [bestScore] and the current
  /// [score] strictly beat it. Suppressed when best-score tracking is
  /// not available so we never show a misleading ribbon.
  ///
  /// A score equal to the previous best is **not** a new best — we
  /// only celebrate strict improvements. The one exception is the
  /// very first recorded play (bestScore == 0 and score > 0), where
  /// any non-zero score is a brand-new personal record.
  bool get _isNewBest {
    final previous = widget.bestScore;
    if (previous == null) return false;
    if (previous == 0) return widget.score > 0;
    return widget.score > previous;
  }

  @override
  void initState() {
    super.initState();
    // Heavy haptic the moment the result lands — reinforces that the
    // round is over and the player just earned something. Skipped on
    // platforms without haptics (no-op there).
    HapticFeedback.heavyImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _awarded) return;
      _awarded = true;
      await _runAwardPipeline();
    });
  }

  /// Runs the same 5-step award pipeline that the previous
  /// `PostGameRewardsScreen` used. Numbers stay identical to the
  /// pre-refactor behavior — this is a lift, not a redesign.
  Future<void> _runAwardPipeline() async {
    final score = widget.score;

    // 1. Standard rewards (coins + XP).
    await ref
        .read(rewardsControllerProvider.notifier)
        .awardForScore(score);

    // 2. Streak bookkeeping.
    await ref.read(streakControllerProvider.notifier).recordSession();

    // 3. Daily challenge bookkeeping. If this is today's featured
    //    game and the score clears the target, the controller emits
    //    on `completedStream` — the global overlay picks that up.
    final updatedChallenge = await ref
        .read(dailyChallengeControllerProvider.notifier)
        .recordCompletion(gameId: widget.gameId, score: score);

    // 4. Daily-completion bonus coin award.
    int bonus = 0;
    if (updatedChallenge != null && updatedChallenge.isCompleted) {
      final justCompleted = score >= updatedChallenge.targetScore &&
          score >= updatedChallenge.bestScore;
      if (justCompleted) {
        bonus = GameEndModal.dailyBonusForScore(score);
        await ref
            .read(rewardsControllerProvider.notifier)
            .addCoins(bonus);
      }
    }

    // 5. Achievement bookkeeping.
    final gameCategory = resolveGameCategory(ref, widget.gameId);
    ref.read(playHistoryControllerProvider.notifier).recordPlay(gameCategory);
    await ref
        .read(playedGamesControllerProvider.notifier)
        .recordPlay(widget.gameId);
    final ctx = buildAchievementContext(ref);
    await ref
        .read(achievementsControllerProvider.notifier)
        .recordSession(ctx: ctx);

    if (!mounted) return;
    setState(() {
      _coinsEarned = GameEndModal.coinsForScore(score);
      _xpEarned = GameEndModal.xpForScore(score);
      _dailyBonus = bonus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncGame = ref.watch(gameByIdProvider(widget.gameId));
    final title = asyncGame.maybeWhen(
      data: (g) => g?.title ?? 'Game',
      orElse: () => 'Game',
    );
    final newLevel = const RewardsCurve().levelFor(
      ref.watch(rewardsControllerProvider).xp,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _TrophyHeader(),
                  AppSpacing.gapLg,
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary(theme.brightness),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapSm,
                  Text(
                    'You scored',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.textSecondary(theme.brightness),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.gapSm,
                  if (_isNewBest)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _NewBestRibbon(),
                    ),
                  Center(
                    child: AnimatedCountUp(
                      target: widget.score,
                      textStyle: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                      duration: const Duration(milliseconds: 900),
                    ),
                  ),
                  AppSpacing.gapLg,
                  _RewardRow(
                    icon: Icons.monetization_on_rounded,
                    color: AppColors.accent,
                    label: 'coins',
                    value: _coinsEarned,
                  ),
                  AppSpacing.gapSm,
                  _RewardRow(
                    icon: Icons.bolt_rounded,
                    color: AppColors.primary,
                    label: 'XP',
                    value: _xpEarned,
                  ),
                  if (_dailyBonus > 0) ...[
                    AppSpacing.gapSm,
                    _RewardRow(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.dailyGold,
                      label: 'daily bonus',
                      value: _dailyBonus,
                    ),
                  ],
                  AppSpacing.gapMd,
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shield_moon_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'You are now Level $newLevel',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AppSpacing.gapXl,
                  PrimaryButton(
                    label: 'Play Again',
                    icon: Icons.replay_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Push a fresh player route on top so the user can
                      // pop back to the rewards screen if they hit back.
                      context.push(
                        '${AppRoutes.gamePlayer}/${widget.gameId}',
                      );
                    },
                  ),
                  AppSpacing.gapSm,
                  SecondaryButton(
                    label: 'Back to Home',
                    icon: Icons.home_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.home);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trophy gradient circle at the top of the results modal. Lifted
/// verbatim from the previous [PostGameRewardsScreen] so the visual
/// identity stays identical.
class _TrophyHeader extends StatelessWidget {
  const _TrophyHeader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accent.withValues(alpha: 0.95),
              AppColors.accent.withValues(alpha: 0.65),
            ],
          ),
        ),
        child: const Icon(
          Icons.emoji_events_rounded,
          size: 64,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Reward row with an [AnimatedCountUp] chip. Public so other surfaces
/// (settings, profile) can show the same chip style if they ever need to.
class GameEndRewardRow extends StatelessWidget {
  const GameEndRewardRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            AppSpacing.gapSm,
            Flexible(
              child: AnimatedCountUp(
                target: value,
                prefix: '+',
                suffix: ' $label',
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// File-private alias so the modal body stays terse.
typedef _RewardRow = GameEndRewardRow;

/// Pill-shaped ribbon that appears above the score when the player
/// just set a new personal best. Uses the daily-gold token so it
/// reads as a celebration distinct from the purple level-up chip
/// further down.
class _NewBestRibbon extends StatelessWidget {
  const _NewBestRibbon();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.dailyGold, AppColors.accent],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'NEW BEST!',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}