import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../core/visual_identity/game_icon_painter.dart';
import '../../../data/models/game_model.dart';
import 'game_category_visual.dart';

/// Shared card used in the category grid, the home horizontal row,
/// and the search results.
///
/// Always renders inside an outer widget that supplies a finite width
/// (a `GridView` tile or a fixed-width `SizedBox`). The layout is
/// intentionally defensive so a long English title ("Ludo Royale") or
/// a long Bangla title ("লুডো রয়েল") never overflows the available
/// height.
///
/// Layout from top to bottom:
///
/// 1. Thumbnail tile — a rounded square filled with the category
///    gradient and a large centered Material icon. The gradient is
///    category-specific (see [GameCategoryVisual]) so cards read as
///    distinct even before real thumbnail art ships.
/// 2. Optional corner ribbon ("NEW" / "POPULAR") overlaid on the top
///    edge of the thumbnail. Only renders when the game is flagged.
/// 3. Title (English) — single line, ellipsized.
/// 4. Subtitle (Bangla) — single line, ellipsized, slightly smaller.
/// 5. Duration badge — single line.
///
/// Everything below the thumbnail is wrapped in [Flexible] so the
/// card remains within the parent's height even at the smallest
/// responsive tile size.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.borderRadius = 16,
    this.thumbnailAspectRatio = 4 / 3,
  });

  final Game game;
  final VoidCallback onTap;

  /// Corner radius applied to the thumbnail and the parent ink
  /// container.
  final double borderRadius;

  /// Width-to-height ratio of the colored placeholder thumbnail.
  /// Tuned so the text rows below always fit at the smallest grid
  /// tile size (see `childAspectRatio: 0.72` in
  /// `category_detail_screen.dart`).
  final double thumbnailAspectRatio;

  /// Show the canonical "coming soon" SnackBar. Callers gate their
  /// `onTap` on `game.comingSoon` so the placeholder card never
  /// navigates to the player screen.
  static void snackComingSoon(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          AppLocalizations.of(context).comingSoonTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = GameCategoryVisual.gradientFor(game.category);
    // Icon resolution order:
    //   1. Flagship titles get a hand-tuned custom-painted icon at 64px.
    //   2. Per-game recipe from the seed (if any) renders via
    //      GameIconTile at 72px so the painter's shape vocabulary
    //      reads cleanly at thumbnail scale.
    //   3. Fall back to the category Material icon at 56px.
    final flagshipIcon = GameCategoryVisual.flagshipIconFor(game.id);
    final recipeIcon = game.iconRecipe == null
        ? null
        : GameIconTile(recipe: game.iconRecipe!, size: 72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            // outlineVariant stays visible on white in light mode and
            // reads as a soft hairline in dark mode — better than the
            // previous outline+0.4α which disappeared on background.
            border: Border.all(
              color: game.comingSoon
                  ? theme.colorScheme.outline
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          // Tighter padding (was AppSpacing.md on all sides). The
          // thumbnail carries the visual weight, so the text block
          // only needs enough side padding to align the title with
          // the inner radius of the thumbnail.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: thumbnailAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background gradient + centered icon. Flagship
                      // titles render with a custom-painted glyph at
                      // 64px; everything else uses the category
                      // Material icon at 56px.
                      Container(
                        decoration: BoxDecoration(gradient: gradient),
                        alignment: Alignment.center,
                        child: flagshipIcon ??
                            recipeIcon ??
                            Icon(
                              GameCategoryVisual.iconFor(game.category),
                              size: 56,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                      ),
                      // Coming-soon flag desaturates the entire thumbnail
                      // so the card reads as "not playable yet" without
                      // shipping unrelated gameplay. The desaturate
                      // matrix is the standard luminance-preserving
                      // greyscale recipe (no alpha reshape).
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
                      // Coming-soon ribbon wins over NEW/POPULAR — the
                      // whole point is to tell the user "this card is
                      // not playable yet", so the badge set is
                      // mutually exclusive.
                      if (game.comingSoon && game.showComingSoonBadge)
                        Positioned(
                          top: AppSpacing.xs,
                          right: AppSpacing.xs,
                          child: GameCardBadge(
                            label: 'COMING SOON',
                            accent: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (game.isNew || game.isPopular)
                        Positioned(
                          top: AppSpacing.xs,
                          right: AppSpacing.xs,
                          child: GameCardBadge(
                            label: game.isPopular ? 'POPULAR' : 'NEW',
                            accent: game.isPopular
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF22D3EE),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Tightened gap rhythm below the thumbnail so the
              // badge stripe and title row don't crowd each other.
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: Text(
                  game.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              // Short colored underline accent beneath the title.
              // Only rendered when the card actually has an upgraded
              // icon (per-game recipe or flagship) — keeps legacy
              // cards (no recipe, no flagship icon) visually unchanged
              // and signals "this card has a custom illustration".
              // Width is fixed so the stripe always reads as a
              // deliberate accent, not a full underline.
              if (game.iconRecipe != null ||
                  GameCategoryVisual.flagshipIds.contains(game.id)) ...[
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: GameCategoryVisual.accentColorFor(game.category),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  game.titleBangla,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${game.avgSessionMinutes} min',
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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

/// Small corner ribbon shown on the top-right of the thumbnail when a
/// game is flagged as new or popular. Defaults to a translucent
/// black pill with white uppercase text — the [accent] color tints
/// the pill background via a low-alpha overlay so it reads against
/// any gradient underneath.
class GameCardBadge extends StatelessWidget {
  const GameCardBadge({
    super.key,
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: 0.85),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
