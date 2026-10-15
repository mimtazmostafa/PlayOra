import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/floating_background_shapes.dart';
import '../../data/registry/game_registry.dart';
import 'widgets/daily_challenge_card.dart';
import 'widgets/hero_banner.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/registry_game_grid.dart';
import 'widgets/section_header.dart';

/// PlayNest — the redesigned Home tab.
///
/// Layout (top → bottom):
///
///   1. **Top bar** — gamepad logo + PlayNest title + avatar.
///   2. **Hero banner** — sky-blue gradient with a friendly blob
///      mascot and "Play More Games Be Happier!" + "Start Playing →".
///   3. **Popular Games** section — 4-column grid of the first 8
///      games in the registry.
///   4. **New & Featured** section header + horizontal "Treasure Hunt"
///      promotional card.
///   5. Bottom nav (Home / Categories / Rewards / More) is owned by
///      [BottomNavShell] which wraps this screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: FloatingBackgroundShapes(
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: HomeTopBar()),
              const SliverToBoxAdapter(child: _FeaturedHero()),
              const SliverToBoxAdapter(child: DailyChallengeCard()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Popular Games',
                  onSeeAll: () => context.push(
                    '/all-games',
                    extra: {'section': 'all'},
                  ),
                ),
              ),
              RegistryGameGrid(
                games: GameRegistry.nonDaily.take(8).toList(),
                childAspectRatio: 0.78,
              ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'New & Featured',
                  onSeeAll: () => context.push(
                    '/all-games',
                    extra: {'section': 'all'},
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: _TreasureHuntPromo()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedHero extends StatelessWidget {
  const _FeaturedHero();

  @override
  Widget build(BuildContext context) {
    final game = GameRegistry.gameOfTheDay;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: HeroBanner(
        game: game,
        onPlay: () =>
            context.push('${AppRoutes.gamePlayer}/${game.id}'),
      ),
    );
  }
}

/// Horizontal promotional card for "Treasure Hunt" — matches the
/// reference image's "New & Featured" entry: pirate character on a
/// light blue card with "Find the treasures and win rewards!" +
/// "Play Now →" CTA.
class _TreasureHuntPromo extends StatelessWidget {
  const _TreasureHuntPromo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            '${AppRoutes.gamePlayer}/treasure-hunt',
          ),
          child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE0F2FE),
              Color(0xFFBAE6FD),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0EA5E9).withValues(alpha: 0.20),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Pirate character silhouette on the left.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 140,
              child: CustomPaint(painter: _PirateSilhouettePainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                150,
                20,
                20,
                20,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Treasure Hunt',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find the treasures\nand win rewards!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.play,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.play.withValues(alpha: 0.30),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Play Now',
                                style: AppTypography.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

/// Simple pirate silhouette painter — used inside the Treasure Hunt
/// promo card to evoke the reference image without needing a bitmap
/// asset.
class _PirateSilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Body — warm brown shirt.
    final shirt = Paint()..color = const Color(0xFF8B4513);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.20, h * 0.55, w * 0.60, h * 0.45),
        const Radius.circular(8),
      ),
      shirt,
    );

    // Head — tan circle.
    final head = Paint()..color = const Color(0xFFE8B98C);
    canvas.drawCircle(Offset(w * 0.50, h * 0.45), w * 0.16, head);

    // Hat — black pirate hat.
    final hat = Paint()..color = const Color(0xFF1F2937);
    final hatPath = Path()
      ..moveTo(w * 0.28, h * 0.40)
      ..lineTo(w * 0.72, h * 0.40)
      ..lineTo(w * 0.62, h * 0.20)
      ..lineTo(w * 0.38, h * 0.20)
      ..close();
    canvas.drawPath(hatPath, hat);

    // Skull emblem — cream circle with eyes on the hat.
    final skull = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawCircle(Offset(w * 0.50, h * 0.28), w * 0.06, skull);
    canvas.drawCircle(
      Offset(w * 0.47, h * 0.27),
      w * 0.015,
      Paint()..color = const Color(0xFF1F2937),
    );
    canvas.drawCircle(
      Offset(w * 0.53, h * 0.27),
      w * 0.015,
      Paint()..color = const Color(0xFF1F2937),
    );

    // Treasure chest at the bottom — gold body with brown rim.
    final chest = Paint()..color = const Color(0xFFFFC837);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, h * 0.78, w * 0.30, h * 0.18),
        const Radius.circular(4),
      ),
      chest,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.40, h * 0.83, w * 0.30, h * 0.02),
      Paint()..color = const Color(0xFF8B4513),
    );
  }

  @override
  bool shouldRepaint(_PirateSilhouettePainter old) => false;
}
