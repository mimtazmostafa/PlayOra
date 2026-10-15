import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/registry/game_registry.dart';

/// Universal card used across the Home rows, Categories screen,
/// and Search results. Renders one [RegistryGame].
///
/// Layout (top → bottom):
///
///   * 4:3 art placeholder with the emoji glyph and a tinted
///     gradient background derived from [RegistryGame.accentColor].
///   * Optional "2P" corner badge for two-player titles.
///   * Title (English) — single line, ellipsized.
///   * Subtitle (Bangla) — single line, ellipsized.
///   * Meta row — difficulty dot + minutes badge.
///
/// Every text node is wrapped with overflow guards so long titles
/// ("Cricket Batting Challenge") never blow the tile height on
/// 360dp-wide phones.
class RegistryGameCard extends StatelessWidget {
  const RegistryGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.compact = false,
  });

  final RegistryGame game;
  final VoidCallback onTap;

  /// When `true`, the card uses tighter padding for use inside
  /// horizontal scrollers where vertical space is precious.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(game.accentColor);
    final padding = compact ? AppSpacing.sm : AppSpacing.md;
    final titleStyle = (compact
            ? theme.textTheme.titleSmall
            : theme.textTheme.titleMedium)
        ?.copyWith(fontWeight: FontWeight.w800);
    final subtitleStyle = (compact
            ? theme.textTheme.bodySmall
            : theme.textTheme.bodySmall)
        ?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Art placeholder ───
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent.withValues(alpha: 0.35),
                              accent.withValues(alpha: 0.10),
                            ],
                          ),
                        ),
                      ),
                      // Emoji glyph, large.
                      Center(
                        child: Text(
                          game.emoji,
                          style: const TextStyle(fontSize: 44),
                        ),
                      ),
                      // 2P corner ribbon.
                      if (game.isTwoPlayer)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _PillBadge(
                            text: '2P',
                            color: AppColors.feature,
                            textColor: AppColors.onColoredSurface,
                          ),
                        ),
                      // Difficulty dot.
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _DifficultyDot(level: game.difficulty),
                      ),
                    ],
                  ),
                ),
              ),
              // ─── Metadata ───
              Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.titleBangla,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${game.avgSessionMinutes} min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.text,
    required this.color,
    required this.textColor,
  });
  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

class _DifficultyDot extends StatelessWidget {
  const _DifficultyDot({required this.level});

  /// We can't import [GameDifficulty] here as a value without a
  /// string switch — keep the lookup in a small map for clarity.
  final dynamic level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level.toString()) {
      'GameDifficulty.easy' => AppColors.play,
      'GameDifficulty.medium' => AppColors.reward,
      'GameDifficulty.hard' => AppColors.error,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
