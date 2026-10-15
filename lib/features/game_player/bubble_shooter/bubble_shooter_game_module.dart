import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'bubble_shooter_controller.dart';
import 'bubble_shooter_game.dart';

/// GameModule implementation for the Bubble Shooter game.
///
/// Holds the [BubbleShooterController] in a [StatefulWidget] whose
/// [State] implements [GameModule]. The host grabs the State via a
/// `GlobalKey<BubbleShooterGameModuleState>`.
class BubbleShooterGameModule extends StatefulWidget {
  const BubbleShooterGameModule({
    super.key,
    required this.gameTitle,
  });

  final String gameTitle;

  @override
  State<BubbleShooterGameModule> createState() => BubbleShooterGameModuleState();
}

class BubbleShooterGameModuleState extends State<BubbleShooterGameModule>
    with TickerProviderStateMixin
    implements GameModule {
  late final BubbleShooterController _controller;
  bool _initialized = false;

  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  BubbleShooterController get controller => _controller;

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
    _controller = BubbleShooterController(vsync: this);
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
    _controller.dispose();
    _initialized = false;
  }

  @override
  Widget build(BuildContext context) {
    // Auto-init so the module starts ticking the moment it's mounted.
    if (!_initialized) init();
    return BubbleShooterGame(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}
