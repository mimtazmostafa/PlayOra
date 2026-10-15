import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Semantic haptic intensity. We define our own enum (rather than
/// reaching for `HapticFeedbackType` from the Flutter source — which
/// is not a public Dart type) so mini-games can ask the host to fire
/// the right `HapticFeedback.*Impact` without knowing about the host
/// implementation.
enum HapticFeedbackType { light, medium, heavy, selection }

/// Shared aspect for all mini-game widgets.
///
/// Every game implements a [MiniGame] widget that:
///   * paints its own canvas (no theme dependency)
///   * reports score via [onScoreChanged] (debounced)
///   * reports secondary stats via [onStatsChanged] (optional —
///     defaults to a no-op so legacy games keep working)
///   * reports end-of-match via [onGameOver] (exactly once)
///   * triggers haptics via [onHaptic] when state changes
///
/// Games never know about the universal container — they receive
/// callbacks and forward them. This keeps each game trivially
/// testable and embeddable.
class MiniGameCallbacks {
  const MiniGameCallbacks({
    required this.onScoreChanged,
    required this.onGameOver,
    required this.onHaptic,
    this.onStatsChanged,
  });

  final ValueChanged<int> onScoreChanged;

  /// Optional secondary-stats reporter. Mini-games that show extra
  /// counters (moves, balls, shots, etc.) call this whenever the value
  /// changes so the host HUD can show it as a subtitle without the
  /// game having to render its own chip row.
  final ValueChanged<String>? onStatsChanged;

  final VoidCallback onGameOver;
  final ValueChanged<HapticFeedbackType> onHaptic;
}

/// Forwarded for backwards compatibility — bare-color helpers used
/// across many minigame files. Defaults to the **dark-mode** palette
/// (deep navy) which preserves the original "solid dark canvas"
/// behaviour when callers don't pass a [Brightness].
Color kGameBackground([Brightness? brightness]) =>
    AppColors.background(brightness ?? Brightness.dark);

Color kGameAccent([Brightness? brightness]) => AppColors.play;

Color kGameSecondary([Brightness? brightness]) => AppColors.feature;

Color kGameReward([Brightness? brightness]) => AppColors.reward;

Color kGamePanel([Brightness? brightness]) =>
    AppColors.surfaceVariant(brightness ?? Brightness.dark);

/// Convenience palette on a [BuildContext]. Resolves all chrome
/// tokens in one shot so games can read `context.kGame.background`
/// instead of having to thread `Brightness` through every painter.
extension GameChromeContext on BuildContext {
  GameChrome get kGame => GameChrome.of(this);
}

/// Brightness-resolved bundle of chrome tokens. Preferred over the
/// bare-[kGameBackground]-style helpers for new code.
class GameChrome {
  const GameChrome({
    required this.background,
    required this.accent,
    required this.secondary,
    required this.reward,
    required this.panel,
    required this.onBackground,
    required this.onSurfaceMuted,
    required this.outline,
    required this.brightness,
  });

  factory GameChrome.of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return GameChrome(
      background: AppColors.background(brightness),
      accent: AppColors.play,
      secondary: AppColors.feature,
      reward: AppColors.reward,
      panel: AppColors.surfaceVariant(brightness),
      onBackground: AppColors.textPrimary(brightness),
      onSurfaceMuted: AppColors.textSecondary(brightness),
      outline: AppColors.outline(brightness),
      brightness: brightness,
    );
  }

  final Color background;
  final Color accent;
  final Color secondary;
  final Color reward;
  final Color panel;
  final Color onBackground;
  final Color onSurfaceMuted;
  final Color outline;
  final Brightness brightness;
}