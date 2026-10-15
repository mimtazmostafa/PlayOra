import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'chess_controller.dart';
import 'chess_game.dart';

/// GameModule shim for the Chess Master mini-game. Mirrors the
/// Ludo pattern: the host owns a [GlobalKey<ChessGameModuleState>]
/// and drives init/pause/resume/tearDown through it.
class ChessGameModule extends StatefulWidget {
  const ChessGameModule({super.key, required this.gameTitle});

  final String gameTitle;

  @override
  State<ChessGameModule> createState() => ChessGameModuleState();
}

class ChessGameModuleState extends State<ChessGameModule>
    implements GameModule {
  late final ChessController _controller;
  bool _initialized = false;
  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  ChessController get controller => _controller;

  @override
  void Function(int score) get onGameEnd => _onGameEnd;

  @override
  set onGameEnd(void Function(int score) callback) {
    _onGameEnd = callback;
    if (_initialized) _controller.attachEndCallback(callback);
  }

  @override
  void initState() {
    super.initState();
    _controller = ChessController();
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
    if (!_initialized) return;
    _controller.tearDown();
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) init();
    return ChessGame(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}