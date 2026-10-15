import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'game_module.dart';

/// Placeholder module for HTML5/WebView games.
///
/// The real `flutter_inappwebview` integration is wired up in a separate
/// commit; this stub renders a friendly "coming soon" card so the rest of
/// the Game Player shell (pause overlay, post-game flow, routing) can be
/// exercised end-to-end against [GameModule] without a browser runtime.
///
/// Lifecycle behavior mirrors what the real WebView module will do:
///   - init()    — no-op (no async load yet)
///   - pause()   — no-op (nothing playing yet)
///   - resume()  — no-op
///   - tearDown() — no-op
class WebViewGameModule extends StatefulWidget {
  const WebViewGameModule({
    super.key,
    required this.title,
    required this.entryPoint,
  });

  /// Display name of the game, shown on the placeholder card.
  final String title;

  /// Asset path or remote URL — opaque to this stub.
  final String entryPoint;

  @override
  State<WebViewGameModule> createState() => WebViewGameModuleState();
}

/// Public State class — the host grabs the GameModule via a
/// `GlobalKey<WebViewGameModuleState>` and calls the contract methods on it.
class WebViewGameModuleState extends State<WebViewGameModule>
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
                    color: AppColors.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.public_rounded,
                    size: 36,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                AppSpacing.gapLg,
                Text(
                  'WebView games coming soon',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapSm,
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapMd,
                Text(
                  'HTML5 games load in an embedded WebView. The runtime '
                  'integration lands in the next milestone — this screen '
                  'is here so the rest of the player flow works.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.gapMd,
                Text(
                  'Source: ${widget.entryPoint}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}