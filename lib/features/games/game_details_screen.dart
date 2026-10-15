import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/visual_identity/game_icon_painter.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/models/game_category.dart';
import '../../data/models/game_difficulty.dart';
import '../../data/models/game_model.dart';
import '../../l10n/generated/app_localizations.dart';
import '../favorites/favorites_controller.dart';
import 'games_providers.dart';
import 'widgets/game_card.dart';
import 'widgets/game_category_visual.dart';
import 'widgets/level_select_grid.dart';

/// Final Game Details screen.
///
/// Sections, top-to-bottom:
///   1. Hero preview (16:9 gradient w/ title initial)
///   2. Title row (English + Bangla + favorite heart)
///   3. Badges (category, difficulty, offline, session length)
///   4. Description
///   5. Expandable "How to Play"
///   6. Related games row (same category, excluding current)
///   7. Sticky bottom "Play" button
///
/// Tap "Play" → push the Game Player route (built next).
class GameDetailsScreen extends ConsumerStatefulWidget {
  const GameDetailsScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends ConsumerState<GameDetailsScreen> {
  bool _howToPlayExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncGame = ref.watch(gameByIdProvider(widget.gameId));
    final asyncRelated = ref.watch(relatedGamesProvider(widget.gameId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Details'),
      ),
      body: asyncGame.when(
        data: (game) {
          if (game == null) {
            return Center(
              child: Text(
                'Game "${widget.gameId}" not found.',
                style: theme.textTheme.bodyLarge,
              ),
            );
          }
          return Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  // Leave room for the sticky Play button (height + 2*padding).
                  AppSpacing.xxxl + AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroPreview(game: game),
                    const SizedBox(height: AppSpacing.lg),
                    _TitleRow(game: game),
                    const SizedBox(height: AppSpacing.md),
                    _BadgeRow(game: game),
                    const SizedBox(height: AppSpacing.xl),
                    if (game.comingSoon) ...[
                      _ComingSoonBanner(game: game),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      game.description.isEmpty
                          ? 'Description coming soon.'
                          : game.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _HowToPlaySection(
                      text: game.howToPlay,
                      expanded: _howToPlayExpanded,
                      onToggle: () => setState(
                        () => _howToPlayExpanded = !_howToPlayExpanded,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _LevelSelectSection(game: game),
                    const SizedBox(height: AppSpacing.xl),
                    asyncRelated.when(
                      data: (related) => related.isEmpty
                          ? const SizedBox.shrink()
                          : _RelatedGamesRow(games: related),
                      loading: () => const SizedBox(height: 140),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              _StickyPlayBar(game: game),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Failed to load game: $e',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero preview
// -----------------------------------------------------------------------------

/// Big banner at the top of the details screen.
///
/// Mirrors the icon-resolution chain used by [GameCard] so flagship
/// titles (Ludo, Chess, Sudoku, Cricket, Carrom, Call Break) render
/// their hand-tuned painter at scale, per-game recipe games render
/// via [GameIconTile], and unmapped titles fall back to a stylized
/// first-letter glyph.
///
/// The frame is a 16:9 gradient stack:
///   - base: category-specific gradient (matches the rest of the app)
///   - mid: radial glow centered behind the icon, so the icon never
///     sits on an empty color block
///   - top: the icon itself, centered
///
/// Coming-soon titles apply the same desaturation overlay as
/// [GameCard] so the hero reads consistently with the rest of the
/// coming-soon UI.
class _HeroPreview extends StatelessWidget {
  const _HeroPreview({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same fallback chain as GameCard: flagship → recipe → first letter.
    // Sized so the painter reads at ~96px against the 16:9 hero — large
    // enough to be the focal point without crowding the title row
    // underneath.
    final Widget? flagshipIcon =
        GameCategoryVisual.flagshipIconFor(game.id);
    final Widget? recipeIcon = game.iconRecipe == null
        ? null
        : GameIconTile(recipe: game.iconRecipe!, size: 96);

    final Widget icon = flagshipIcon ??
        recipeIcon ??
        Text(
          game.title.isNotEmpty ? game.title[0].toUpperCase() : '?',
          style: theme.textTheme.displayLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Category gradient base — gives flagship titles the
            //    same warm-to-cool ramp as the rest of the catalog.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: GameCategoryVisual.gradientFor(game.category),
              ),
            ),
            // 2. Radial glow centered behind the icon. Uses the
            //    brand gold at low alpha so the highlight reads as
            //    a warm spotlight, not a foreign color.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 0.95,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.22),
                    AppColors.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // 3. Icon, centered.
            Align(alignment: Alignment.center, child: icon),
            // 4. Coming-soon desaturation, identical recipe to GameCard
            //    so a player tapping in from the grid sees the same
            //    "not playable yet" treatment.
            if (game.comingSoon)
              IgnorePointer(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0, 0, 0, 1, 0,
                  ]),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Title row + favorite heart
// -----------------------------------------------------------------------------

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFav = ref.watch(
      favoritesControllerProvider.select((s) => s.contains(game.id)),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                game.titleBangla,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _FavoriteHeart(
          gameId: game.id,
          isFavorite: isFav,
          onChanged: () => ref
              .read(favoritesControllerProvider.notifier)
              .toggle(game.id),
        ),
      ],
    );
  }
}

class _FavoriteHeart extends StatelessWidget {
  const _FavoriteHeart({
    required this.gameId,
    required this.isFavorite,
    required this.onChanged,
  });

  final String gameId;
  final bool isFavorite;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      child: IconButton(
        tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        onPressed: onChanged,
        iconSize: 28,
        padding: const EdgeInsets.all(AppSpacing.sm),
        constraints: const BoxConstraints(),
        icon: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isFavorite
              ? theme.colorScheme.error
              // Outline heart on a plain light surface — onSurfaceVariant
              // is pinned to a shade that clears 4.5:1 in both modes.
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Badges (category / difficulty / offline / session)
// -----------------------------------------------------------------------------

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _CategoryBadge(category: game.category),
        _DifficultyBadge(difficulty: game.difficulty),
        _SessionBadge(minutes: game.avgSessionMinutes),
        if (game.isOfflineAvailable) const _OfflineBadge(),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final GameCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Badge(
      label: _labelFor(category),
      icon: Icons.category_rounded,
      background: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      foreground: theme.colorScheme.onPrimaryContainer,
    );
  }

  static String _labelFor(GameCategory c) {
    switch (c) {
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

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.difficulty});

  final GameDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = _colorsFor(theme, difficulty);
    return _Badge(
      label: _labelFor(difficulty),
      icon: Icons.speed_rounded,
      background: bg,
      foreground: fg,
    );
  }

  static String _labelFor(GameDifficulty d) {
    switch (d) {
      case GameDifficulty.easy:
        return 'Easy';
      case GameDifficulty.medium:
        return 'Medium';
      case GameDifficulty.hard:
        return 'Hard';
    }
  }

  static (Color, Color) _colorsFor(ThemeData theme, GameDifficulty d) {
    // Raw green/red on their tinted backgrounds score ~2.0:1 / 3.1:1 in
    // light mode — switch to the darker "ink" shade so the badge label
    // clears WCAG AA. Dark mode keeps the bright tone for contrast
    // against the dark surface.
    final dark = theme.brightness == Brightness.dark;
    switch (d) {
      case GameDifficulty.easy:
        return (
          AppColors.secondary.withValues(alpha: 0.18),
          dark ? AppColors.secondary : AppColors.secondaryInk,
        );
      case GameDifficulty.medium:
        return (
          AppColors.accent.withValues(alpha: 0.25),
          dark ? AppColors.accent : AppColors.accentInk,
        );
      case GameDifficulty.hard:
        return (
          AppColors.error.withValues(alpha: 0.16),
          dark ? AppColors.error : AppColors.errorInk,
        );
    }
  }
}

class _SessionBadge extends StatelessWidget {
  const _SessionBadge({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Badge(
      label: '$minutes min/session',
      icon: Icons.timer_outlined,
      background: theme.colorScheme.surfaceContainerHighest,
      foreground: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Badge(
      label: 'Offline',
      icon: Icons.wifi_off_rounded,
      background: theme.colorScheme.surfaceContainerHighest,
      foreground: theme.colorScheme.onSurfaceVariant,
    );
  }
}

// -----------------------------------------------------------------------------
// How to Play (expandable)
// -----------------------------------------------------------------------------

class _HowToPlaySection extends StatelessWidget {
  const _HowToPlaySection({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'How to Play',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Related games
// -----------------------------------------------------------------------------

class _RelatedGamesRow extends StatelessWidget {
  const _RelatedGamesRow({required this.games});

  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Related Games',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            itemCount: games.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) =>
                _RelatedGameTile(game: games[i]),
          ),
        ),
      ],
    );
  }
}

class _RelatedGameTile extends StatelessWidget {
  const _RelatedGameTile({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Icon resolution mirrors GameCard: flagship painter > per-game
    // recipe > first-letter fallback for completely unmapped titles.
    final Widget? flagshipIcon =
        GameCategoryVisual.flagshipIconFor(game.id);
    final Widget? recipeIcon = game.iconRecipe == null
        ? null
        : GameIconTile(recipe: game.iconRecipe!, size: 56);
    return InkWell(
      onTap: () {
        if (game.comingSoon) {
          GameCard.snackComingSoon(context);
          return;
        }
        context.push('${AppRoutes.gameDetails}?id=${game.id}');
      },
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: flagshipIcon ??
                        recipeIcon ??
                        Text(
                          game.title.isNotEmpty
                              ? game.title[0].toUpperCase()
                              : '?',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                  ),
                  // Mirror GameCard's coming-soon desaturation so the
                  // related row reads consistently with the main grid.
                  if (game.comingSoon)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.matrix(<double>[
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0,      0,      0,      1, 0,
                          ]),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              game.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            Text(
              game.titleBangla,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sticky bottom Play bar
// -----------------------------------------------------------------------------

class _StickyPlayBar extends StatelessWidget {
  const _StickyPlayBar({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    // Coming-soon titles swap the Play CTA for a disabled "Coming
    // soon" button. The button still resolves to the same primary
    // shape so the layout below the scroll view doesn't jump.
    final isComingSoon = game.comingSoon;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        shadowColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: PrimaryButton(
              label: isComingSoon
                  ? AppLocalizations.of(context).comingSoonTitle
                  : 'Play',
              icon: isComingSoon
                  ? Icons.hourglass_top_rounded
                  : Icons.play_arrow_rounded,
              onPressed: isComingSoon
                  ? null
                  : () => context.push(
                        '${AppRoutes.gamePlayer}/${game.id}',
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-of-details banner shown only when [Game.comingSoon] is true.
/// Explains why the Play button is disabled and links to the same
/// localized message rendered in the player placeholder.
class _ComingSoonBanner extends StatelessWidget {
  const _ComingSoonBanner({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.hourglass_top_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.comingSoonTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.comingSoonMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Level select (Phase 4 — shared level progression)
// -----------------------------------------------------------------------------

/// Wraps the [LevelSelectGrid] for this game. Tapping a tile launches
/// the player with the chosen level. We pass the level through a query
/// param so the mini-game can read it on init.
class _LevelSelectSection extends StatelessWidget {
  const _LevelSelectSection({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncSnapshot =
        ProviderScope.containerOf(context, listen: true)
            .read(levelProgressProvider(game.id));
    final snapshot = asyncSnapshot.value;
    if (snapshot == null) return const SizedBox.shrink();
    // Hide the section for endless-mode games (total == 0) — Snake,
    // 2048, etc. use the high-score tracker instead of levels.
    if (snapshot.total <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Levels',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${snapshot.unlocked}/${snapshot.total} unlocked',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LevelSelectGrid(
          gameId: game.id,
          onSelectLevel: (level) {
            context.push(
              '${AppRoutes.gamePlayer}/${game.id}?level=$level',
            );
          },
        ),
      ],
    );
  }
}