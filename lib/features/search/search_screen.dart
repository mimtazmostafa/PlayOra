import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/visual_identity/game_icon_painter.dart';
import '../../data/models/game_category.dart';
import '../../data/models/game_model.dart';
import '../categories/categories_providers.dart';
import '../games/games_providers.dart';
import '../games/widgets/game_card.dart';
import '../games/widgets/game_category_visual.dart';

/// Reactive search over the game catalog. Debounces user input by 250ms so we
/// don't re-run filtering on every keystroke.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Auto-focus the field so the keyboard pops on push.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Called on every keystroke. The 250ms debounce coalesces bursts so the
  /// filter only runs once the user pauses.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  /// Submit (enter / search key on keyboard). Skip the debounce and commit
  /// the query immediately, then record it as a recent search.
  void _onSubmitted(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isNotEmpty) {
      ref.read(recentSearchesControllerProvider.notifier).record(value);
    }
  }

  /// Tapping a recent-search chip commits it as the live query and records it.
  void _applyRecent(String query) {
    _debounce?.cancel();
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    setState(() => _query = query);
    ref.read(recentSearchesControllerProvider.notifier).record(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncGames = ref.watch(gameSearchProvider(_query));
    final recents = ref.watch(recentSearchesControllerProvider);
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          decoration: InputDecoration(
            hintText: 'Search games...',
            border: InputBorder.none,
            isCollapsed: true,
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _debounce?.cancel();
                  _controller.clear();
                  setState(() => _query = '');
                },
              );
            },
          ),
        ],
      ),
      body: asyncGames.when(
        data: (games) {
          if (!hasQuery) {
            return _InviteState(
              recents: recents,
              onApplyRecent: _applyRecent,
              onClearRecents: () =>
                  ref.read(recentSearchesControllerProvider.notifier).clear(),
            );
          }
          if (games.isEmpty) {
            return _EmptyResults(query: _query);
          }
          return _ResultsList(
            games: games,
            query: _query,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Search failed: $e',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteState extends ConsumerWidget {
  const _InviteState({
    required this.recents,
    required this.onApplyRecent,
    required this.onClearRecents,
  });

  final List<String> recents;
  final ValueChanged<String> onApplyRecent;
  final VoidCallback onClearRecents;

  /// Curated trending searches. Static so the empty state has
  /// something to offer even before the player has any history.
  static const _trending = <String>[
    'Sudoku',
    'Ludo',
    'Bubble',
    'Chess',
    'Cricket',
    'Memory',
    'Block',
    'Carrom',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Derive a few "suggested" games from the catalog so the empty
    // state has real artwork, not just text. Falls back gracefully if
    // the catalog is still loading.
    final asyncGames = ref.watch(gamesProvider);
    final suggestions = asyncGames.maybeWhen(
      data: (all) {
        final popular = all.where((g) => g.isPopular).toList();
        final pool = popular.isNotEmpty ? popular : all;
        return pool.take(8).toList(growable: false);
      },
      orElse: () => const <Game>[],
    );

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        if (recents.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Recent searches',
              trailingLabel: 'Clear all',
              onTrailingTap: onClearRecents,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final q in recents)
                    _Chip(
                      icon: Icons.history_rounded,
                      label: q,
                      onTap: () => onApplyRecent(q),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'Trending searches',
            subtitle: 'Quick jumps into popular categories',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in _trending)
                  _Chip(
                    icon: Icons.local_fire_department_rounded,
                    label: t,
                    accent: theme.colorScheme.primary,
                    onTap: () => onApplyRecent(t),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: _SectionHeader(
            title: 'You might like',
            subtitle: 'A few picks from the PlayNest catalog',
          ),
        ),
        if (suggestions.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            sliver: SliverToBoxAdapter(
              child: SizedBox(height: 168),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(
              height: 184,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) {
                  final game = suggestions[i];
                  return SizedBox(
                    width: 140,
                    child: GameCard(
                      game: game,
                      onTap: () => _goToDetails(context, game.id),
                    ),
                  );
                },
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }

  void _goToDetails(BuildContext context, String id) {
    context.push('${AppRoutes.gameDetails}?id=$id');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingLabel != null && onTrailingTap != null)
            TextButton(onPressed: onTrailingTap, child: Text(trailingLabel!)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = accent ?? theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tone.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.games, required this.query});

  final List<Game> games;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: games.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '${games.length} ${games.length == 1 ? 'result' : 'results'} for "$query"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final game = games[i - 1];
        return _ResultTile(
          game: game,
          onTap: () =>
              context.push('${AppRoutes.gameDetails}?id=${game.id}'),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.game, required this.onTap});

  final Game game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resolve a hand-tuned icon first (flagship painters for Ludo,
    // Sudoku, Chess, etc.), then a per-game recipe, then fall back to
    // the styled first-letter chip. Mirrors the resolution chain on
    // Home/Categories so all result rows feel like the same app.
    final Widget? flagship =
        GameCategoryVisual.flagshipIconFor(game.id);
    final Widget? recipe = game.iconRecipe == null
        ? null
        : GameIconTile(recipe: game.iconRecipe!, size: 44);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface,
            border: Border.all(
              color: game.comingSoon
                  ? theme.colorScheme.outline
                  : theme.colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Icon tile. Same 64x64 frame + per-category gradient as
              // the Home/Category thumbnails, so the list visually ties
              // back to the rest of the catalog.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: GameCategoryVisual.gradientFor(game.category),
                ),
                alignment: Alignment.center,
                child: flagship ??
                    recipe ??
                    Text(
                      game.title.isNotEmpty
                          ? game.title[0].toUpperCase()
                          : '?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      game.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.titleBangla,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (game.comingSoon && game.showComingSoonBadge)
                          _BadgeChip(
                            label: 'Coming soon',
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        else
                          _BadgeChip(
                            label: _labelForCategory(game.category),
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
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

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No games match "$query"',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Try a different keyword or browse the full catalog by category.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.games),
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('Browse Games'),
            ),
          ],
        ),
      ),
    );
  }
}
