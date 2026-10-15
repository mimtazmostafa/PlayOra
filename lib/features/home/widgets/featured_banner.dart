import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/visual_identity/game_icon_painter.dart';
import '../../../data/models/game_category.dart';
import '../../../data/models/game_difficulty.dart';
import '../../games/widgets/game_category_visual.dart';
import '../../../data/models/game_model.dart';

/// Auto-scrolling hero carousel for the home screen.
///
/// Pages advance every 4 seconds; tapping a page invokes [onTap].
class FeaturedBanner extends StatefulWidget {
  const FeaturedBanner({
    super.key,
    required this.games,
    required this.onTap,
    this.autoScrollInterval = const Duration(seconds: 4),
  });

  final List<Game> games;
  final ValueChanged<Game> onTap;
  final Duration autoScrollInterval;

  @override
  State<FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends State<FeaturedBanner> {
  late final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant FeaturedBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.games.length != oldWidget.games.length) {
      _controller.jumpToPage(0);
      _index = 0;
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.games.length < 2) return;
    _timer = Timer.periodic(widget.autoScrollInterval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.games.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.games.length,
            itemBuilder: (context, i) => _FeaturedSlide(
              game: widget.games[i],
              onTap: () => widget.onTap(widget.games[i]),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.games.length, (i) {
            final selected = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: selected ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({required this.game, required this.onTap});

  final Game game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _gradientFor(game.category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: accent,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _categoryLabel(game.category),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _difficultyLabel(game.difficulty),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      game.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      game.titleBangla,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // Real icon block — flagship painters first, then the
              // per-game IconRecipe (covers non-flagship titles),
              // finally a letter glyph so the layout never collapses
              // to an empty square.
              _FeaturedIcon(game: game),
            ],
          ),
        ),
      ),
    );
  }

  static List<Color> _gradientFor(GameCategory category) {
    switch (category) {
      case GameCategory.puzzle:
        return const [Color(0xFF4A1FA8), AppColors.primary];
      case GameCategory.arcade:
        return const [Color(0xFFEC4899), Color(0xFFF472B6)];
      case GameCategory.brain:
        return const [Color(0xFF0EA5E9), Color(0xFF38BDF8)];
      case GameCategory.sports:
        return const [AppColors.secondary, Color(0xFF4ADE80)];
      case GameCategory.board:
        return const [AppColors.accent, Color(0xFFFCD34D)];
      case GameCategory.action:
        return const [AppColors.error, Color(0xFFF87171)];
      case GameCategory.racing:
        return const [Color(0xFF8B5CF6), Color(0xFFA78BFA)];
      case GameCategory.strategy:
        return const [Color(0xFF14B8A6), Color(0xFF2DD4BF)];
      case GameCategory.word:
        return const [Color(0xFF0F766E), Color(0xFF14B8A6)];
      case GameCategory.educational:
        return const [Color(0xFFF59E0B), Color(0xFFFBBF24)];
    }
  }

  static String _categoryLabel(GameCategory c) {
    switch (c) {
      case GameCategory.puzzle:
        return 'PUZZLE';
      case GameCategory.arcade:
        return 'ARCADE';
      case GameCategory.brain:
        return 'BRAIN';
      case GameCategory.sports:
        return 'SPORTS';
      case GameCategory.board:
        return 'BOARD';
      case GameCategory.action:
        return 'ACTION';
      case GameCategory.racing:
        return 'RACING';
      case GameCategory.strategy:
        return 'STRATEGY';
      case GameCategory.word:
        return 'WORD';
      case GameCategory.educational:
        return 'EDUCATIONAL';
    }
  }

  static String _difficultyLabel(GameDifficulty d) {
    switch (d) {
      case GameDifficulty.easy:
        return 'EASY';
      case GameDifficulty.medium:
        return 'MEDIUM';
      case GameDifficulty.hard:
        return 'HARD';
    }
  }
}

/// Hero icon block shown on the right edge of each featured slide.
///
/// Resolution order:
/// 1. Flagship bespoke painter (Ludo / Carrom / Chess / etc.)
/// 2. Per-game [IconRecipe] (covers non-flagship titles with the
///    new [GameIconPainter] system)
/// 3. First-letter glyph (last-resort, never allows an empty block)
///
/// The tile is wrapped in a soft white-tinted backdrop so dark
/// icons stay legible against the category gradient.
class _FeaturedIcon extends StatelessWidget {
  const _FeaturedIcon({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final flagship = GameCategoryVisual.flagshipIconFor(game.id);
    final child = flagship ??
        (game.iconRecipe != null
            ? GameIconTile(recipe: game.iconRecipe!, size: 64)
            : Text(
                game.title.isEmpty ? '?' : game.title[0].toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ));
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}