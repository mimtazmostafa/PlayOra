import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../game_module.dart';

/// Honest "Coming soon" placeholder shown for catalog entries that
/// don't yet have a playable module wired up.
///
/// This module exists to eliminate the silent fallthrough path that
/// previously routed every unwired native game to the Match-3 default —
/// if a game in [assets/data/games_seed.json] is flagged `comingSoon`,
/// tapping it lands here, where the player is told exactly what's
/// happening instead of being shown someone else's game.
///
/// Lifecycle methods are no-ops for the same reason
/// [WebViewGameModule]'s are: there's nothing to start, pause, resume,
/// or tear down, but the [GameModule] contract requires the shape.
class ComingSoonGameModule extends StatefulWidget {
  const ComingSoonGameModule({
    super.key,
    required this.gameTitle,
  });

  /// Display name of the game, shown on the placeholder card so the
  /// player knows which title the message refers to. Named
  /// `gameTitle` (matching every other module's convention) so the
  /// dispatcher's call sites read uniformly.
  final String gameTitle;

  @override
  State<ComingSoonGameModule> createState() => ComingSoonGameModuleState();
}

/// Public State class — the host grabs the GameModule via a
/// `GlobalKey<ComingSoonGameModuleState>` and calls the contract
/// methods on it.
class ComingSoonGameModuleState extends State<ComingSoonGameModule>
    implements GameModule {
  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  @override
  void Function(int score) get onGameEnd => _onGameEnd;

  @override
  set onGameEnd(void Function(int score) callback) => _onGameEnd = callback;

  @override
  void init() {}

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void tearDown() {}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    size: 36,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                AppSpacing.gapLg,
                Text(
                  l10n.comingSoonTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapSm,
                Text(
                  widget.gameTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapMd,
                Text(
                  l10n.comingSoonMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}