import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/floating_background_shapes.dart';
import '../../data/registry/game_registry.dart';
import 'widgets/vibrant_game_card.dart';

/// Full catalog grid — opened from the "See All" links on the Home
/// screen. Always renders the entire non-daily catalog in a 4-column
/// responsive grid titled "All Games". The `section` extra is
/// currently treated as a no-op (left in place so any deep-links
/// passing it still land on the same catalog view) but new callers
/// should just push `/all-games` without an `extra`.
class AllGamesScreen extends StatelessWidget {
  const AllGamesScreen({super.key, this.section = 'all'});

  /// Reserved for future filtering. Currently ignored — every See All
  /// link should land on the full catalog regardless of the source
  /// section on Home.
  final String section;

  String _title() {
    switch (section) {
      case 'popular':
        return 'Popular Games';
      case 'new':
        return 'New & Featured';
      default:
        return 'All Games';
    }
  }

  String _subtitle() {
    final n = GameRegistry.nonDaily.length;
    return '$n games ready to play';
  }

  /// Filter the catalog based on the section.
  List<RegistryGame> _games() {
    switch (section) {
      case 'popular':
        return GameRegistry.all
            .where((g) => g.isPopular && !g.id.startsWith('daily-'))
            .toList(growable: false);
      case 'new':
        return GameRegistry.all
            .where((g) => g.isNew && !g.id.startsWith('daily-'))
            .toList(growable: false);
      default:
        return GameRegistry.nonDaily;
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = _games();
    final title = _title();
    final subtitle = _subtitle();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: FloatingBackgroundShapes(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _BackChip(onTap: () => context.pop()),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (games.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videogame_asset_off_rounded,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No games in this section yet',
                            textAlign: TextAlign.center,
                            style: AppTypography.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: games.length,
                    itemBuilder: (context, i) {
                      final game = games[i];
                      return VibrantGameCard(
                        key: ValueKey(game.id),
                        game: game,
                        onTap: () => context.push(
                          '${AppRoutes.gamePlayer}/${game.id}',
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface(theme.brightness),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Convenience for callers that don't care about the section arg.
class AllGamesRouteHelper {
  AllGamesRouteHelper._();

  /// Route path under the home shell. `extra` carries `{section: 'popular' | 'new' | 'all'}`.
  static const String path = '/all-games';
}