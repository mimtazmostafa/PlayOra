import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'game_widgets.dart';

/// Tiny abstract base every mini-game widget implements.
///
/// The dispatcher calls [_attach] once on mount and [_detach] on
/// dispose. Subclasses use [cbs] to report score and end-of-match.
abstract class MiniGame extends StatefulWidget {
  const MiniGame({super.key, required this.callbacks});

  final MiniGameCallbacks callbacks;
}

abstract class MiniGameState<T extends StatefulWidget> extends State<T> {
  /// True after the first frame has been painted.
  bool get mountedAndReady => mounted;

  /// Forward a haptic event through the callbacks.
  ///
  /// The host [GameContainerScreen] pairs every haptic with a matching
  /// audio cue through the global [AudioEngine], so mini-games just
  /// call this method and get both sound + tactile feedback for free.
  void haptic(HapticFeedbackType t) => widget is MiniGame
      // ignore: cast_nullable_to_non_nullable
      ? (widget as MiniGame).callbacks.onHaptic(t)
      : null;

  /// Tell the host the score changed. Callers debounce — the host
  /// compares against the previous value.
  ///
  /// The host's `onScoreChanged` calls `setState` on its own State.
  /// Mini-games frequently trigger [reportScore] from inside their own
  /// `setState` callback (e.g. inside a [Ticker.onTick]), inside a
  /// `CustomPainter.paint`, or directly from a gesture callback that
  /// runs while a parent build is in flight. In any of those cases a
  /// synchronous call to the parent's `setState` throws the dreaded
  /// "setState() or markNeedsBuild() called during build" exception.
  ///
  /// We schedule the host callback for the next frame so the call is
  /// always safe. This makes the API safe-by-default — individual
  /// mini-games don't have to think about it.
  void reportScore(int score) {
    if (!mounted) return;
    if (widget is! MiniGame) return;
    final cbs = (widget as MiniGame).callbacks;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cbs.onScoreChanged(score);
    });
  }

  /// Optional: report a secondary stat (e.g. "Moves 5", "Balls 3") so
  /// the host HUD subtitle stays in sync without the game having to
  /// draw its own chip row.
  ///
  /// Scheduled for the next frame for the same setState-during-build
  /// reasons as [reportScore].
  void reportStats(String label) {
    if (!mounted) return;
    if (widget is! MiniGame) return;
    final cbs = (widget as MiniGame).callbacks;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cbs.onStatsChanged?.call(label);
    });
  }

  /// Tell the host the game ended. Idempotent.
  ///
  /// Scheduled for the next frame for the same setState-during-build
  /// reasons as [reportScore]. This also guards against the
  /// game-over modal being triggered multiple times during a single
  /// physics tick.
  bool _gameOverReported = false;
  void reportGameOver() {
    if (!mounted) return;
    if (_gameOverReported) return;
    if (widget is! MiniGame) return;
    _gameOverReported = true;
    final cbs = (widget as MiniGame).callbacks;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cbs.onGameOver();
    });
  }

  /// Reset the local "game-over already reported" latch — call this
  /// from a mini-game's "Play Again" path so a fresh round can end
  /// the game normally.
  void resetGameOverLatch() {
    _gameOverReported = false;
  }
}
