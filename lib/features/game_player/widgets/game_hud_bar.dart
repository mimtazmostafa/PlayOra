import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Top-of-game HUD bar shared by every playable game.
///
/// Layout (left → right):
///   1. Pause button — only rendered when [onPause] is non-null. The host
///      screen already shows a corner pause button; passing `null` here
///      keeps the bar from showing a duplicate.
///   2. Title + subtitle text block (optional subtitle) → ellipsises safely
///   3. Trailing chips — by default a score chip ([score]) and an optional
///      countdown timer chip ([timerSeconds]). The timer chip flips its
///      colors red when [timerSeconds] ≤ [lowTimeThreshold] so the player
///      feels the urgency without us needing to pass extra state.
///
/// Games that need bespoke trailing content (e.g. Ludo's seat indicator)
/// can pass [scoreChip] / [timerChip] builders instead of the simple
/// `score` / `timerSeconds` shortcuts.
///
/// All games previously implemented their own `_Hud` / `_HudBar` private
/// classes — this widget is the single source of truth.
///
/// **Visual style (capsule refresh):**
/// every surface — pause button, level chip, score chip, timer chip —
/// renders as a floating rounded capsule (`BorderRadius.circular(20)`)
/// with a uniform soft drop shadow (`Offset(0, 4)`, blur 8, opacity
/// 0.15). Active button backgrounds use [AppColors.hudIndigo]; accent
/// text uses [AppColors.hudAccentYellow] so the HUD reads as its own
/// visual layer rather than inheriting the brand primary.
class GameHudBar extends StatelessWidget {
  const GameHudBar({
    super.key,
    required this.title,
    this.onPause,
    this.subtitle,
    this.subtitleColor,
    this.score,
    this.scoreIcon = Icons.star_rounded,
    this.timerSeconds,
    this.lowTimeThreshold = 10,
    this.levelChip,
    this.difficultyChip,
  })  : assert(
          score != null ||
              timerSeconds != null ||
              levelChip != null ||
              difficultyChip != null,
          'GameHudBar needs at least one trailing indicator '
          '(score, timer, levelChip, or difficultyChip).',
        ),
        scoreChip = null,
        timerChip = null,
        customTrailing = null;

  /// Lower-level constructor for games that want fully custom trailing
  /// widgets (e.g. Ludo shows the current seat color, not a score chip).
  /// Pass [scoreChip] / [timerChip] / [customTrailing] — at most one
  /// of those three should be non-null; the first non-null wins.
  const GameHudBar.customTrailing({
    super.key,
    required this.title,
    this.onPause,
    this.subtitle,
    this.subtitleColor,
    this.scoreChip,
    this.timerChip,
    this.customTrailing,
    this.levelChip,
    this.difficultyChip,
  })  : score = null,
        scoreIcon = Icons.star_rounded,
        timerSeconds = null,
        lowTimeThreshold = 10;

  final String title;
  final VoidCallback? onPause;
  final String? subtitle;
  final Color? subtitleColor;

  // ---- Simple trailing API ----
  final int? score;
  final IconData scoreIcon;
  final int? timerSeconds;
  final int lowTimeThreshold;

  /// Optional "Level N" pill rendered next to (or instead of) the
  /// score chip. Set when the host wants the level surfaced in the
  /// central HUD bar.
  final Widget? levelChip;

  /// Optional difficulty pill ("EASY" / "MEDIUM" / "EXTRA HARD").
  final Widget? difficultyChip;

  // ---- Custom trailing API ----
  final Widget? scoreChip;
  final Widget? timerChip;
  final Widget? customTrailing;

  /// Shared shadow for every capsule in the HUD. Defined once here so
  /// adding a new chip only needs a one-line decoration block.
  static const List<BoxShadow> _capsuleShadow = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, AppColors.hudCapsuleShadowOpacity),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  /// Capsule radius — `circular(20)` per the spec rather than the
  /// previous `circular(999)` pill style.
  static const BorderRadius _capsuleRadius =
      BorderRadius.all(Radius.circular(20));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          if (onPause != null) ...[
            _PauseCapsule(onPressed: onPause!, brightness: brightness),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(brightness),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtitleColor ??
                          AppColors.textSecondary(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          _buildTrailing(),
        ],
      ),
    );
  }

  Widget _buildTrailing() {
    if (customTrailing != null) return customTrailing!;
    if (timerSeconds != null) {
      return _TimerChip(
        secondsRemaining: timerSeconds!,
        lowTimeThreshold: lowTimeThreshold,
      );
    }
    if (scoreChip != null) return scoreChip!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (levelChip != null) ...[
          levelChip!,
          const SizedBox(width: 6),
        ],
        if (difficultyChip != null) ...[
          difficultyChip!,
          const SizedBox(width: 6),
        ],
        _ScoreChip(score: score ?? 0, icon: scoreIcon),
      ],
    );
  }
}

/// Pause button — rendered as a floating indigo capsule with a soft
/// drop shadow instead of the previous `IconButton.filledTonal`.
class _PauseCapsule extends StatelessWidget {
  const _PauseCapsule({required this.onPressed, required this.brightness});
  final VoidCallback onPressed;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pause',
      child: Material(
        color: AppColors.hudIndigo,
        shape: const RoundedRectangleBorder(
          borderRadius: GameHudBar._capsuleRadius,
        ),
        elevation: 0,
        child: InkWell(
          onTap: onPressed,
          borderRadius: GameHudBar._capsuleRadius,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: GameHudBar._capsuleRadius,
              boxShadow: GameHudBar._capsuleShadow,
            ),
            child: const Icon(
              Icons.pause_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Level N" pill — small flag icon + numeric level. Used by the host
/// HUD to surface the player's current level when known.
class LevelChip extends StatelessWidget {
  const LevelChip({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = AppColors.hudAccentYellow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: GameHudBar._capsuleRadius,
        border: Border.all(color: fg.withValues(alpha: 0.85), width: 1.2),
        boxShadow: GameHudBar._capsuleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_rounded, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            'Level $level',
            style: TextStyle(
              color: AppColors.textPrimary(brightness),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// "EASY" / "MEDIUM" / "HARD" / "EXTRA HARD" pill — colored by
/// difficulty. Tints the pill background so the player knows what
/// they're getting into at a glance.
class DifficultyChip extends StatelessWidget {
  const DifficultyChip({super.key, required this.difficulty});
  final String difficulty;

  Color _bgFor() {
    return switch (difficulty.toUpperCase()) {
      'EASY' => AppColors.play.withValues(alpha: 0.18),
      'MEDIUM' => AppColors.feature.withValues(alpha: 0.18),
      'HARD' => AppColors.streak.withValues(alpha: 0.18),
      _ => AppColors.error.withValues(alpha: 0.20),
    };
  }

  Color _fgFor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return switch (difficulty.toUpperCase()) {
      'EASY' =>
        brightness == Brightness.dark ? AppColors.play : AppColors.secondaryInk,
      'MEDIUM' => brightness == Brightness.dark
          ? AppColors.feature
          : AppColors.featureInk,
      'HARD' =>
        brightness == Brightness.dark ? AppColors.streak : AppColors.streakInk,
      _ => AppColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fgFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bgFor(),
        borderRadius: GameHudBar._capsuleRadius,
        border: Border.all(color: fg, width: 1.2),
        boxShadow: GameHudBar._capsuleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            difficulty.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal score chip — exposed indirectly via [GameHudBar.score].
/// Kept public-ish so tests can find it; not part of the stable API.
class GameHudScoreChip extends StatelessWidget {
  const GameHudScoreChip({
    super.key,
    required this.score,
    this.icon = Icons.star_rounded,
  });

  final int score;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface(brightness),
        borderRadius: GameHudBar._capsuleRadius,
        border: Border.all(
          color: AppColors.hudIndigo.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: GameHudBar._capsuleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.hudAccentYellow),
          const SizedBox(width: 6),
          Text(
            '$score',
            style: TextStyle(
              color: AppColors.textPrimary(brightness),
              fontWeight: FontWeight.w800,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal timer chip — exposed indirectly via [GameHudBar.timerSeconds].
/// Tints the background/text red when the countdown is at or below
/// [lowTimeThreshold] seconds so the player feels the urgency.
class GameHudTimerChip extends StatelessWidget {
  const GameHudTimerChip({
    super.key,
    required this.secondsRemaining,
    this.lowTimeThreshold = 10,
  });

  final int secondsRemaining;
  final int lowTimeThreshold;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLow = secondsRemaining <= lowTimeThreshold;
    final fg = isLow
        ? AppColors.error
        : AppColors.hudAccentYellow;
    final bg = isLow
        ? AppColors.error.withValues(alpha: 0.18)
        : AppColors.surface(brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: GameHudBar._capsuleRadius,
        border: Border.all(color: fg, width: 1.2),
        boxShadow: GameHudBar._capsuleShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            '${secondsRemaining}s',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// File-private aliases so the build helper can stay terse.
typedef _ScoreChip = GameHudScoreChip;
typedef _TimerChip = GameHudTimerChip;