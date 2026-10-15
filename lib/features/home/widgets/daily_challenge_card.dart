import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../data/registry/game_registry.dart';
import '../../daily_challenge/daily_challenge_controller.dart';
import '../../daily_challenge/daily_challenge_model.dart';

/// Today's "Daily Challenge" card on the home screen.
///
/// Shows the game the deterministic picker chose for today, the
/// target score, and the user's best (with a check when cleared).
/// Tapping "Play Now" routes to the game details screen.
class DailyChallengeCard extends ConsumerWidget {
  const DailyChallengeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenge = ref.watch(dailyChallengeControllerProvider);
    if (challenge == null) return const SizedBox.shrink();

    // Look up the registry entry so the card can show its title. The
    // picker resolves to a `daily-*` id which is registered in the
    // new GameRegistry (not the legacy Game catalog).
    final RegistryGame? registryGame = GameRegistry.byId(challenge.gameId);
    if (registryGame == null) return const SizedBox.shrink();

    return _DailyChallengeCardView(
      game: registryGame,
      challenge: challenge,
      onPlay: () => _openGame(context, registryGame),
    );
  }

  static void _openGame(BuildContext context, RegistryGame game) {
    // Routed through GoRouter (not Navigator.pushNamed) so the
    // deep-link uses the same query-param contract as every other
    // launcher tap. The dispatcher routes `daily-*` ids to the base
    // game with `dailyChallenge: true`.
    context.push('${AppRoutes.gamePlayer}/${game.id}');
  }
}

class _DailyChallengeCardView extends StatelessWidget {
  const _DailyChallengeCardView({
    required this.game,
    required this.challenge,
    required this.onPlay,
  });

  final RegistryGame game;
  final DailyChallenge challenge;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = challenge.isCompleted;
    final progressLabel = isDone
        ? 'Cleared! ${challenge.bestScore} pts'
        : 'Best: ${challenge.bestScore} / Goal ${challenge.targetScore}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent, Color(0xFFF59E0B)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isDone
                      ? Icons.emoji_events_rounded
                      : Icons.bolt_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Daily Challenge',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Purple fill + white label so the button stays visible
              // on the gold gradient underneath (~10:1 contrast) instead
              // of disappearing into a white-on-gold button (~1.9:1).
              // No fixed width: the button is sized to its label, the
              // Expanded text column above gets first claim on remaining
              // width, and the longest title in the seed ("Shadow
              // Fighter", 15 chars) fits before any ellipsis kicks in.
              IntrinsicWidth(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: const Color(0xFF4A1FA8),
                          onPrimary: Colors.white,
                        ),
                  ),
                  child: PrimaryButton(
                    label: isDone ? 'Play Again' : 'Play Now',
                    onPressed: onPlay,
                    expand: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}