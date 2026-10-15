import 'package:flutter/widgets.dart';

/// Contract every game (native Flutter or WebView) implements.
///
/// Lifecycle:
///   - [init] is called exactly once after the module is built and
///     before the first frame is painted. Use it to seed state, kick off
///     animations, start timers, load assets.
///   - [pause] is called when the player loses focus (back button tapped,
///     app backgrounded, route swap). Implementations MUST stop ticking
///     timers and freeze animations here.
///   - [resume] is the counterpart to pause — restart whatever was frozen.
///   - [tearDown] runs when the module is permanently removed from the tree.
///     Stop everything; release controllers.
///
/// End-of-game:
///   - When the game decides it is over, it MUST call [onGameEnd] exactly
///     once. The score argument is forwarded to the host shell, which
///     navigates to the Post-Game Rewards screen.
abstract class GameModule {
  /// Triggered exactly once, after first build. Implementations should
  /// start the game clock / first animation here.
  void init();

  /// Stop gameplay — freeze timers, pause animations, mute audio.
  /// Safe to call multiple times.
  void pause();

  /// Counterpart to [pause]. No-op if the module was never paused.
  void resume();

  /// Permanently tear down the module. Stops everything and releases
  /// resources. Implementations should not throw if called twice.
  void tearDown();

  /// Widget rendered by the host. The host treats this as opaque.
  Widget build(BuildContext context);

  /// Notifies the host that the game has ended. Implementations MUST
  /// guard against double-calls (the host relies on a single push to
  /// the rewards screen).
  void Function(int score) get onGameEnd;

  /// Sets the end-of-game callback supplied by the host.
  set onGameEnd(void Function(int score) callback);
}