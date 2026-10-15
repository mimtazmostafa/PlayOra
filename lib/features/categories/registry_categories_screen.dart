import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/game_category.dart';
import '../../data/registry/game_registry.dart';
import '../games/widgets/registry_game_card.dart';

/// Categories tab — vertical scroll of category sections, each
/// rendering its games in a responsive 2-column grid.
///
/// This is the **registry-driven** counterpart to the existing
/// `CategoriesScreen` — the existing screen still exists and routes
/// here for the new Games tab. Each tap routes to the universal
/// `GameContainerScreen` with the registry id.
class RegistryCategoriesScreen extends StatelessWidget {
  const RegistryCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Build a list of `(category, games)` pairs but only for
    // categories that have ≥ 1 game in the registry — keeps the
    // screen from showing empty sections.
    final groups = <_CategoryGroup>[];
    for (final c in GameCategory.values) {
      final games = GameRegistry.inCategory(c)
          .where((g) => !g.id.startsWith('daily-'))
          .toList(growable: false);
      if (games.isNotEmpty) {
        groups.add(_CategoryGroup(category: c, games: games));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Games'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: groups.length,
        itemBuilder: (context, i) => _CategorySection(group: groups[i]),
      ),
    );
  }
}

class _CategoryGroup {
  const _CategoryGroup({required this.category, required this.games});
  final GameCategory category;
  final List<RegistryGame> games;

  String get label => switch (category) {
        GameCategory.puzzle => 'Puzzle',
        GameCategory.arcade => 'Arcade',
        GameCategory.brain => 'Brain',
        GameCategory.sports => 'Sports',
        GameCategory.board => 'Board',
        GameCategory.action => 'Action',
        GameCategory.racing => 'Racing',
        GameCategory.strategy => 'Strategy',
        GameCategory.word => 'Word',
        GameCategory.educational => 'Educational',
      };

  Color get accent => switch (category) {
        GameCategory.puzzle => AppColors.feature,
        GameCategory.arcade => AppColors.play,
        GameCategory.brain => AppColors.reward,
        GameCategory.sports => AppColors.play,
        GameCategory.board => AppColors.feature,
        GameCategory.action => AppColors.error,
        GameCategory.racing => AppColors.feature,
        GameCategory.strategy => AppColors.feature,
        GameCategory.word => const Color(0xFF14B8A6),
        GameCategory.educational => AppColors.play,
      };
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.group});

  final _CategoryGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: group.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  group.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${group.games.length} games',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, c) {
              // 2 columns on phones; the registry's per-game `accentColor`
              // keeps each tile visually distinct even at the smallest
              // tile size.
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: group.games.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, i) => RegistryGameCard(
                  game: group.games[i],
                  onTap: () => _launchGame(context, group.games[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static void _launchGame(BuildContext context, RegistryGame game) {
    context.push('${AppRoutes.gamePlayer}/${game.id}');
  }
}
