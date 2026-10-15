import 'package:flutter/material.dart';

import '../../game_player/chess/chess_controller.dart';
import '../../game_player/chess/chess_game.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// Thin adapter that wraps the existing `ChessGame` widget (which lives
/// on the `ChessController` `ChangeNotifier` surface) behind the
/// dispatcher-friendly `MiniGame` callback interface.
///
/// The chess module is one of the two "legacy" surfaces in the
/// codebase (alongside `LudoModule`) — it already has a complete
/// rules engine, alpha-beta search, and bot-driven `ChangeNotifier`
/// controller. The dispatcher is the bulk surface for the other 18
/// games. Rather than duplicate the entire chess implementation, this
/// adapter:
///   1. Creates a `ChessController` in `initState` and tears it down
///      in `dispose`.
///   2. Hooks the controller's end-of-match callback so when the
///      game ends we forward `reportScore(score)` +
///      `reportGameOver()` to the host.
///   3. Renders `ChessGame(controller: ...)` inside its own
///      scaffold-less black surface so the host `GameContainerScreen`
///      can keep showing the HUD without nesting two Scaffolds.
class ChessAdapterGame extends MiniGame {
  const ChessAdapterGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  final int level;

  @override
  State<ChessAdapterGame> createState() => _ChessAdapterGameState();
}

class _ChessAdapterGameState extends MiniGameState<ChessAdapterGame> {
  late final ChessController _controller;
  bool _endedFired = false;

  ChessBotDifficulty _difficultyForLevel(int lvl) {
    // 1-3 → easy, 4-6 → medium, 7+ → hard. Gives level progression a
    // tangible meaning without an invasive settings screen.
    if (lvl <= 3) return ChessBotDifficulty.easy;
    if (lvl <= 6) return ChessBotDifficulty.medium;
    return ChessBotDifficulty.hard;
  }

  @override
  void initState() {
    super.initState();
    _controller = ChessController(
      difficulty: _difficultyForLevel(widget.level),
    );
    _controller.attachEndCallback(_onGameEnd);
    // Forward any subsequent restarts/difficulty tweaks to the host so
    // the HUD subtitle stays in sync with the live game state.
    _controller.addListener(_onControllerChanged);
    // The controller schedules its first bot tick in init(); the
    // widget renders the board even before init() runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.init();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.tearDown();
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Reflect the running match into the host HUD subtitle ("Turn
    // White" / "Turn Black"). The string is informational only —
    // `reportStats` is a no-op if the host hasn't wired it.
    final state = _controller.currentState;
    if (_controller.hasEnded) {
      // Don't overwrite the game-over flow; reportScore handles it.
      return;
    }
    final side = state.sideToMove.name; // "white" / "black"
    final fullmove = state.fullmoveNumber;
    final stats = 'Turn ${side[0].toUpperCase()}${side.substring(1)}'
        ' • Move $fullmove';
    reportStats(stats);
  }

  void _onGameEnd(int score) {
    if (_endedFired) return;
    _endedFired = true;
    reportScore(score);
    reportGameOver();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kGameBackground(Theme.of(context).brightness),
      child: ChessGame(
        gameTitle: 'Chess Master',
        controller: _controller,
      ),
    );
  }
}
