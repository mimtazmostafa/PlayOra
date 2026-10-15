import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/game_category.dart';
import '../../data/models/game_model.dart';
import '../games/games_providers.dart';
import '../games/widgets/game_card.dart';
import 'category_sort.dart';

/// Lists every game in [GameCategory], with a sort dropdown.
///
/// Sort options are static (Popular / New / Quick Play <2 min) — the catalog
/// doesn't carry play counts or release dates yet, so "Popular" / "New"
/// reuse seed-file order.
class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({super.key, required this.category});

  final GameCategory category;

  @override
  ConsumerState<CategoryDetailScreen> createState() =>
      _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  CategorySort _sort = CategorySort.popular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncGames = ref.watch(gamesByCategoryProvider(widget.category));

    return Scaffold(
      appBar: AppBar(
        title: Text(_labelForCategory(widget.category)),
        actions: [
          PopupMenuButton<CategorySort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final s in CategorySort.values)
                PopupMenuItem<CategorySort>(
                  value: s,
                  child: Row(
                    children: [
                      if (s == _sort)
                        Icon(Icons.check_rounded,
                            size: 18,
                            color: theme.colorScheme.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(s.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: asyncGames.when(
        data: (games) {
          final sorted = sortGames(games, _sort);
          if (sorted.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No games in this category yet.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              _SortBanner(
                sort: _sort,
                count: sorted.length,
                onTap: () => _showSortSheet(context),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.lg,
                    crossAxisSpacing: AppSpacing.lg,
                    // Taller tile gives the title + Bangla subtitle
                    // + duration pill enough room to render without
                    // clipping. The thumbnail's `AspectRatio(4/3)`
                    // inside `GameCard` was tuned alongside this
                    // value to fit the longest catalog entry
                    // (Ludo Royale / 25 min).
                    childAspectRatio: 0.72,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final game = sorted[i];
                    return GameCard(
                      game: game,
                      onTap: () => _openDetails(context, game),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Failed to load games: $e',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sort by',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final s in CategorySort.values)
              ListTile(
                leading: Icon(
                  s == _sort
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(s.label),
                onTap: () {
                  setState(() => _sort = s);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context, Game game) {
    if (game.comingSoon) {
      GameCard.snackComingSoon(context);
      return;
    }
    context.push('${AppRoutes.gameDetails}?id=${game.id}');
  }

  static String _labelForCategory(GameCategory category) {
    switch (category) {
      case GameCategory.puzzle:
        return 'Puzzle';
      case GameCategory.arcade:
        return 'Arcade';
      case GameCategory.brain:
        return 'Brain';
      case GameCategory.sports:
        return 'Sports';
      case GameCategory.board:
        return 'Board';
      case GameCategory.action:
        return 'Action';
      case GameCategory.racing:
        return 'Racing';
      case GameCategory.strategy:
        return 'Strategy';
      case GameCategory.word:
        return 'Word';
      case GameCategory.educational:
        return 'Educational';
    }
  }
}

class _SortBanner extends StatelessWidget {
  const _SortBanner({
    required this.sort,
    required this.count,
    required this.onTap,
  });

  final CategorySort sort;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'game' : 'games'} · Sorted by ${sort.label}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
