import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/registry/game_registry.dart';
import '../../games/widgets/registry_game_card.dart';

/// Horizontal scrollable row of registry games.
///
/// Renders a section header with title and count, followed by a
/// `ListView` of [RegistryGameCard]s sized for the Home dashboard.
///
/// Used for: Quick Play buckets, Popular, Play Together, Bangladesh
/// Hub, Brain & Puzzle.
class RegistryRow extends StatelessWidget {
  const RegistryRow({
    super.key,
    required this.title,
    required this.emoji,
    required this.games,
    this.onSeeAll,
    this.accent,
  });

  final String title;
  final String emoji;
  final List<RegistryGame> games;
  final VoidCallback? onSeeAll;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowAccent = accent ?? theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: rowAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: games.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => SizedBox(
              width: 160,
              child: RegistryGameCard(
                game: games[i],
                compact: true,
                onTap: () {
                  context.push('${AppRoutes.gamePlayer}/${games[i].id}');
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Vertical grid used when the row is "wide" (e.g. on tablets) or
/// when the home dashboard wants to pack more games into one section.
class RegistryGrid extends StatelessWidget {
  const RegistryGrid({
    super.key,
    required this.title,
    required this.emoji,
    required this.games,
    this.accent,
  });

  final String title;
  final String emoji;
  final List<RegistryGame> games;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.7,
            ),
            itemBuilder: (context, i) => RegistryGameCard(
              game: games[i],
              compact: true,
              onTap: () {
                context.push('${AppRoutes.gamePlayer}/${games[i].id}');
              },
            ),
          ),
        ],
      ),
    );
  }
}
