import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/game_model.dart';
import '../../data/models/game_type.dart';
import '../games/games_providers.dart';
import 'block_puzzle/block_puzzle_game_module.dart';
import 'bubble_shooter/bubble_shooter_game_module.dart';
import 'ludo/ludo_game_module.dart';
import 'memory_match/memory_match_game_module.dart';
import 'webview_game_module.dart';
import 'widgets/coming_soon_module.dart';
import 'widgets/game_end_modal.dart';
import 'widgets/game_pause_overlay.dart';

/// Entry points that map to specific native Flutter modules.
///
/// Each catalog entry whose `gameType` is `nativeFlutter` routes
/// through this table. Anything missing here, or anything whose
/// [Game.comingSoon] is `true`, is routed to
/// [ComingSoonGameModule] — there is no silent fallback to unrelated
/// gameplay.
///
/// Adding a new native game = add an entry here + branch in
/// [_buildNativeModule].
class _NativeDispatch {
  _NativeDispatch._();
  static const String blockPuzzle = '/game/block-puzzle';
  static const String memoryMatch = '/game/memory-match';
  static const String ludo = '/game/ludo-royale';
  static const String bubbleShooter = '/game/bubble-pop';
}

/// Host shell for any playable game.
///
/// Reads the `gameId` from the route, looks up the [Game] in the catalog,
/// and dispatches to the appropriate [GameModule] implementation:
///   - game.comingSoon == true           → [ComingSoonGameModule]
///   - entryPoint in `_NativeDispatch`    → matching native module
///   - any other nativeFlutter entry     → [ComingSoonGameModule]
///                                          (honest "not implemented" placeholder)
///   - [GameType.webview]                → [WebViewGameModule]
///                                          (honest "HTML5 runtime pending" placeholder)
///
/// Adds three things on top of the module:
///   1. A pause overlay (Resume / Quit to Details / Quit to Home) — shown
///      via [GamePauseOverlay.show] which provides a fade+scale-in animation.
///   2. A pop-scope so the system back button pauses instead of popping.
///   3. A `onGameEnd(score)` handler that shows [GameEndModal] over the
///      game screen (replacing the previous pushReplacement to a separate
///      rewards route).
class GamePlayerScreen extends ConsumerStatefulWidget {
  const GamePlayerScreen({super.key, required this.gameId});

  final String gameId;

  @override
  ConsumerState<GamePlayerScreen> createState() => _GamePlayerScreenState();
}

class _GamePlayerScreenState extends ConsumerState<GamePlayerScreen> {
  // Each module branch needs a key whose runtime type matches its State
  // class. Flutter stores keys in an internal map keyed on runtime type,
  // so a `GlobalKey<BlockPuzzleGameModuleState>` cannot be passed off as
  // a `GlobalKey<LudoGameModuleState>` — the downcast throws at runtime.
  // We therefore hold lazily-initialized typed keys and expose the
  // active one through [_activeModule].
  GlobalKey<BlockPuzzleGameModuleState>? _blockPuzzleKey;
  GlobalKey<MemoryMatchGameModuleState>? _memoryMatchKey;
  GlobalKey<LudoGameModuleState>? _ludoKey;
  GlobalKey<BubbleShooterGameModuleState>? _bubbleShooterKey;
  GlobalKey<ComingSoonGameModuleState>? _comingSoonKey;
  GlobalKey<WebViewGameModuleState>? _webViewKey;
  bool _pausePending = false;
  bool _ended = false;

  /// The State of whichever module is currently mounted, regardless of
  /// which typed key created it. Returns null before first frame.
  State? get _activeModule =>
      _blockPuzzleKey?.currentState ??
      _memoryMatchKey?.currentState ??
      _ludoKey?.currentState ??
      _bubbleShooterKey?.currentState ??
      _comingSoonKey?.currentState ??
      _webViewKey?.currentState;

  /// Single end-of-game handler. Assigned to the module's `onGameEnd` setter
  /// each build so the module always has a live callback to fire.
  void _handleGameEnd(int score) {
    if (_ended) return;
    _ended = true;
    final module = _activeModule;
    if (module != null) _invokeLifecycle(module, 'tearDown');
    if (!mounted) return;
    GameEndModal.show(
      context,
      gameId: widget.gameId,
      score: score,
    );
  }

  void _pauseModule() {
    final module = _activeModule;
    if (module == null) return;
    _invokeLifecycle(module, 'pause');
  }

  void _resumeModule() {
    final module = _activeModule;
    if (module == null) return;
    _invokeLifecycle(module, 'resume');
  }

  /// Reflection-free lifecycle dispatch. We only know the State implements
  /// GameModule at the call site, so the host goes through the same shape.
  void _invokeLifecycle(State module, String method) {
    // All live module States (BlockPuzzle, MemoryMatch, Ludo,
    // BubbleShooter, ComingSoon, WebView) implement GameModule. We
    // duck-type through `dynamic` to keep this host free of concrete
    // module imports beyond the dispatch table above.
    final dynamic m = module;
    switch (method) {
      case 'pause':
        m.pause();
        break;
      case 'resume':
        m.resume();
        break;
      case 'tearDown':
        m.tearDown();
        break;
    }
  }

  Future<void> _showPauseDialog() async {
    final game = ref.read(gameByIdProvider(widget.gameId)).value;
    _pauseModule();
    await GamePauseOverlay.show(
      context,
      onResume: () async {
        _resumeModule();
      },
      onQuitToDetails: () async {
        final module = _activeModule;
        if (module != null) _invokeLifecycle(module, 'tearDown');
        _pausePending = false;
        if (mounted && game != null) {
          context.go('${AppRoutes.gameDetails}?id=${game.id}');
        }
      },
      onQuitToHome: () async {
        final module = _activeModule;
        if (module != null) _invokeLifecycle(module, 'tearDown');
        _pausePending = false;
        if (mounted) context.go(AppRoutes.home);
      },
    );
    // If the dialog was dismissed via the scrim without picking one of
    // the three actions, resume the module so the player isn't stuck.
    if (mounted && !_ended) {
      _resumeModule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncGame = ref.watch(gameByIdProvider(widget.gameId));

    // Attach `_handleGameEnd` to the module each build so the callback is
    // always wired up to the live State. The setter is idempotent on the
    // module side (it just overwrites the callback field).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final module = _activeModule;
      if (module == null) return;
      final dynamic m = module;
      m.onGameEnd = _handleGameEnd;
    });

    return PopScope(
      // Block the default back behavior — show the pause overlay instead.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_pausePending || _ended) return;
        _pausePending = true;
        _showPauseDialog();
      },
      child: Scaffold(
        backgroundColor: AppColors.background(theme.brightness),
        body: SafeArea(
          child: asyncGame.when(
            data: (game) => _buildLoaded(theme, game),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Could not load game: $err',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(ThemeData theme, Game? game) {
    if (game == null) {
      return Center(
        child: Text(
          'Game "${widget.gameId}" not found.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    final moduleWidget = _buildModule(game);

    return Stack(
      children: [
        Positioned.fill(child: moduleWidget),
        // Pause toggle in the corner — overlaid on top of whatever the
        // module renders so every game (real, coming-soon, or webview
        // placeholder) has a guaranteed entry point into the pause
        // dialog.
        Positioned(
          top: AppSpacing.sm,
          left: AppSpacing.sm,
          child: _PauseButton(
            onTap: () {
              if (_pausePending || _ended) return;
              _pausePending = true;
              _showPauseDialog();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModule(Game game) {
    switch (game.gameType) {
      case GameType.nativeFlutter:
        return _buildNativeModule(game);
      case GameType.webview:
        return WebViewGameModule(
          key: _webViewKey ??= GlobalKey<WebViewGameModuleState>(),
          title: game.title,
          entryPoint: game.entryPoint,
        );
    }
  }

  /// Route a native Flutter game to its specialized module. Each module
  /// has a distinct `State` type so we can't share one `GlobalKey`; the
  /// `switch` rebuilds the right key for each branch.
  ///
  /// The `comingSoon` flag short-circuits the dispatch — a game marked
/// as coming-soon always goes to [ComingSoonGameModule] regardless of
  /// its `entryPoint`. Anything whose entryPoint is not in
  /// `_NativeDispatch` also lands on [ComingSoonGameModule]; there is no
  /// silent fallback to unrelated gameplay.
  Widget _buildNativeModule(Game game) {
    if (game.comingSoon) {
      return ComingSoonGameModule(
        key: _comingSoonKey ??= GlobalKey<ComingSoonGameModuleState>(),
        gameTitle: game.title,
      );
    }
    switch (game.entryPoint) {
      case _NativeDispatch.blockPuzzle:
        return BlockPuzzleGameModule(
          key: _blockPuzzleKey ??= GlobalKey<BlockPuzzleGameModuleState>(),
          gameTitle: game.title,
        );
      case _NativeDispatch.memoryMatch:
        return MemoryMatchGameModule(
          key: _memoryMatchKey ??= GlobalKey<MemoryMatchGameModuleState>(),
          gameTitle: game.title,
        );
      case _NativeDispatch.ludo:
        return LudoGameModule(
          key: _ludoKey ??= GlobalKey<LudoGameModuleState>(),
          gameTitle: game.title,
        );
      case _NativeDispatch.bubbleShooter:
        return BubbleShooterGameModule(
          key: _bubbleShooterKey ??=
              GlobalKey<BubbleShooterGameModuleState>(),
          gameTitle: game.title,
        );
      default:
        // Native entry whose route is not in `_NativeDispatch` —
        // show the honest "Coming soon" placeholder rather than
        // shipping unrelated gameplay under a wrong label.
        return ComingSoonGameModule(
          key: _comingSoonKey ??= GlobalKey<ComingSoonGameModuleState>(),
          gameTitle: game.title,
        );
    }
  }
}

/// Small icon-button overlay that opens the pause dialog. Lives in the
/// host (not in the shared widgets folder) because it positions itself
/// absolutely over whichever module is mounted and needs a 1-line
/// layout — extracting it would just add indirection without payoff.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface(theme.brightness).withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(
            Icons.pause_rounded,
            size: 24,
          ),
        ),
      ),
    );
  }
}
