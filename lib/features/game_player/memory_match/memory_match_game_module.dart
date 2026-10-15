import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'memory_match_controller.dart';
import 'memory_match_game.dart';

/// GameModule implementation for the Memory Match mini-game.
class MemoryMatchGameModule extends StatefulWidget {
  const MemoryMatchGameModule({
    super.key,
    required this.gameTitle,
  });

  final String gameTitle;

  @override
  State<MemoryMatchGameModule> createState() => MemoryMatchGameModuleState();
}

class MemoryMatchGameModuleState extends State<MemoryMatchGameModule>
    with SingleTickerProviderStateMixin
    implements GameModule {
  late final MemoryMatchController _controller;
  bool _initialized = false;

  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  MemoryMatchController get controller => _controller;

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
    _controller = MemoryMatchController(vsync: this);
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
    return MemoryMatchGame(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}