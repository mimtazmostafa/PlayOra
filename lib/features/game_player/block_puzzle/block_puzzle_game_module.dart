import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'block_puzzle_controller.dart';
import 'block_puzzle_game.dart';

/// GameModule implementation for the Block Puzzle mini-game.
///
/// Mirrors [Match3GameModule] — the widget tree holds the
/// [BlockPuzzleController], and we expose the GameModule contract on
/// the [State] so the host can drive init/pause/resume/tearDown through
/// a [GlobalKey].
class BlockPuzzleGameModule extends StatefulWidget {
  const BlockPuzzleGameModule({
    super.key,
    required this.gameTitle,
  });

  final String gameTitle;

  @override
  State<BlockPuzzleGameModule> createState() => BlockPuzzleGameModuleState();
}

/// Public State — the host grabs this via
/// `GlobalKey<BlockPuzzleGameModuleState>` and calls the contract.
class BlockPuzzleGameModuleState extends State<BlockPuzzleGameModule>
    with SingleTickerProviderStateMixin
    implements GameModule {
  late final BlockPuzzleController _controller;
  bool _initialized = false;

  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  BlockPuzzleController get controller => _controller;

  @override
  void Function(int score) get onGameEnd => _onGameEnd;

  @override
  set onGameEnd(void Function(int score) callback) {
    _onGameEnd = callback;
    if (_initialized) {
      _controller.attachEndCallback(callback);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = BlockPuzzleController(vsync: this);
  }

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    _controller.attachEndCallback(_onGameEnd);
    _controller.init();
  }

  @override
  void pause() {
    if (!_initialized) return;
    _controller.pause();
  }

  @override
  void resume() {
    if (!_initialized) return;
    _controller.resume();
  }

  @override
  void tearDown() {
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) init();
    return BlockPuzzleGame(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}
