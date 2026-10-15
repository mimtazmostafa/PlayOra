import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/registry/game_registry.dart';
import '../../favorites/favorites_controller.dart';
import '../../games/widgets/game_artwork.dart';

/// Clean, friendly game card — solid pastel-coloured thumbnail with
/// the game title below (matches the PlayNest reference).
///
/// Visual recipe (light theme):
///
///   * Rounded squircle thumbnail filled with a vibrant gradient
///     (accent → 25 % darker variant).
///   * `GameArtwork` recipe drawn centered on the gradient — the
///     same colorful vector icons used in the PlayNest launcher's
///     game grid.
///   * Bold dark title (Poppins w900) below the thumbnail.
///   * Multi-layered drop-shadows on the card body for a "floating"
///     feel (`cardShadowColor` + tight inner shadow).
///
/// A heart icon in the top-right of the thumbnail toggles the
/// favourite state (mirrors the behaviour on the game-detail screen).
/// Tapping anywhere else on the card fires [onTap].
class VibrantGameCard extends ConsumerStatefulWidget {
  const VibrantGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.borderRadius = AppSpacing.cardRadius,
    this.showFavoriteToggle = true,
  });

  final RegistryGame game;
  final VoidCallback onTap;
  final double borderRadius;

  /// When `true` (default) a heart chip sits in the thumbnail's
  /// top-right corner. Set to `false` for screens that already have
  /// their own tap-to-favourite mechanism.
  final bool showFavoriteToggle;

  @override
  ConsumerState<VibrantGameCard> createState() => _VibrantGameCardState();
}

class _VibrantGameCardState extends ConsumerState<VibrantGameCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final brightness = Theme.of(context).brightness;
    final gradient = _gradientFor(game, brightness);

    return Semantics(
      button: true,
      label: '${game.title}, ${game.avgSessionMinutes} minute game',
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap,
            onHighlightChanged: (v) {
              if (mounted) setState(() => _pressed = v);
            },
            child: Container(
              decoration: BoxDecoration(
                color: brightness == Brightness.dark
                    ? const Color(0xFF1B2440)
                    : Colors.white,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: brightness == Brightness.dark
                    ? const [
                        BoxShadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 8),
                          spreadRadius: 2,
                          blurRadius: 16,
                        ),
                        BoxShadow(
                          color: Color(0x33000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ]
                    : const [
                        BoxShadow(
                          color: AppColors.cardShadowColor,
                          offset: Offset(0, 8),
                          spreadRadius: 2,
                          blurRadius: 16,
                        ),
                        BoxShadow(
                          color: Color(0x0A000000),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(widget.borderRadius),
                        topRight: Radius.circular(widget.borderRadius),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(gradient: gradient),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: GameArtwork(
                              id: game.id,
                              accent: Colors.white,
                              size: double.infinity,
                              cornerRadius: 14,
                              padding: 4,
                              transparent: true,
                            ),
                          ),
                          if (widget.showFavoriteToggle)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: _FavoriteToggle(gameId: game.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: brightness == Brightness.dark
                            ? Colors.white
                            : AppColors.textPrimaryLight,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Vibrant gradient — accent color blending into a darker variant
  /// for the bottom-right. Direction mirrors the reference design's
  /// top-left → bottom-right diagonals.
  static LinearGradient _gradientFor(
    RegistryGame game,
    Brightness brightness,
  ) {
    final base = Color(game.accentColor);
    final hsl = HSLColor.fromColor(base);
    final darker = hsl
        .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
        .toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [base, darker],
    );
  }
}

/// Compact favourite chip rendered on the corner of a game card.
/// Tapping it toggles membership in the favourites set; it stops the
/// tap from bubbling up to the card so the game doesn't launch.
class _FavoriteToggle extends ConsumerWidget {
  const _FavoriteToggle({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(isFavoriteProvider(gameId));
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(favoritesControllerProvider.notifier).toggle(gameId);
        },
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFav ? AppColors.play : Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }
}
