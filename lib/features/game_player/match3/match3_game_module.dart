import 'package:flutter/widgets.dart';

import '../game_module.dart';
import 'match3_controller.dart';
import 'match3_game.dart';

/// GameModule implementation for the Match-3 mini-game.
///
/// The widget tree holds its own [Match3Controller] (which drives the
/// ticker + animations). We wrap that widget in a [StatefulWidget] whose
/// [State] implements [GameModule], so the host can drive init / pause /
/// resume through a [GlobalKey].
///
/// Lifecycle:
///   - [initState] creates a real [Match3Controller] backed by this
///     State's [TickerProvider] (via [SingleTickerProviderStateMixin]).
///   - The widget tree below us binds to that controller and rebuilds
///     every frame.
///   - When the host calls [pause] / [resume], the controller freezes /
///     thaws the ticker.
///   - When the host calls [dispose], the controller disposes with us.
class Match3GameModule extends StatefulWidget {
  const Match3GameModule({
    super.key,
    required this.gameTitle,
  });

  final String gameTitle;

  @override
  State<Match3GameModule> createState() => Match3GameModuleState();
}

/// Public State class — the host grabs the GameModule via a
/// `GlobalKey<Match3GameModuleState>` and calls the contract methods on it.
class Match3GameModuleState extends State<Match3GameModule>
    with SingleTickerProviderStateMixin
    implements GameModule {
  late final Match3Controller _controller;
  bool _initialized = false;

  void Function(int score) _onGameEnd = _noopEnd;
  static void _noopEnd(int score) {}

  /// Exposed for tests that want to drive the controller directly.
  Match3Controller get controller => _controller;

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
    _controller = Match3Controller(vsync: this);
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
    // Auto-init so the module starts ticking the moment it's mounted.
    if (!_initialized) init();
    return Match3Game(
      gameTitle: widget.gameTitle,
      controller: _controller,
    );
  }
}
