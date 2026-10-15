import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'ludo_controller.dart';
import 'ludo_game.dart';

/// GameModule implementation for the Ludo Royale mini-game.
///
/// Mirrors [BlockPuzzleGameModule] / [MemoryMatchGameModule] — the
/// widget tree holds the [LudoController], and we expose the
/// [GameModule] contract on the [State] so the host shell can drive
/// init/pause/resume/tearDown through a [GlobalKey].
///
/// The Ludo controller is fully self-driven: it owns its own bot
/// timers and animation controllers, so [init] simply delegates to
/// the controller's [init] (which kicks off the first bot move if
/// the human is not the first seat) and [pause]/[resume] cancel /
/// resume those internal timers. [tearDown] disposes the
/// controller's [AnimationController]s.
class LudoGameModule extends StatefulWidget {
  const LudoGameModule({
    super.key,
    required this.gameTitle,
  });

  final String gameTitle;

  @override
  State<LudoGameModule> createState() => LudoGameModuleState();
}

/// Public State — the host grabs this via
/// `GlobalKey<LudoGameModuleState>` and calls the contract.
class LudoGameModuleState extends State<LudoGameModule>
    implements GameModule {
  late final LudoController _controller;
  bool _initialized = false;

  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  LudoController get controller => _controller;

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
    // LudoController is pure-Dart + Flutter-light — no vsync needed
    // because all of its AnimationControllers are created lazily
    // inside the controller itself (it owns its own TickerProvider).
    _controller = LudoController();
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
    return LudoGame(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}