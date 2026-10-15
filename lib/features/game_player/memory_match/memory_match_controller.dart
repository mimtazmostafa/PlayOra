import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'memory_match_state.dart';

/// Top-level controller for Memory Match.
///
/// Pure logic lives in [MemoryMatchLogic]. The controller owns:
///   - the [MemoryMatchState]
///   - a 1-second timer (for the elapsed-seconds counter)
///   - a one-shot delay (for the post-flip auto-flip-back animation)
///   - the end-of-game callback
class MemoryMatchController extends ChangeNotifier {
  MemoryMatchController({
    required TickerProvider vsync,
    MemoryMatchLogic? logic,
  })  : _vsync = vsync,
        logic = logic ?? MemoryMatchLogic() {
    _state = this.logic.newGame();
    _ticker = vsync.createTicker(_onTick);
  }

  // ignore: unused_field
  final TickerProvider _vsync;
  final MemoryMatchLogic logic;
  late final Ticker _ticker;
  late MemoryMatchState _state;

  /// Frames elapsed since the last flip. Used to schedule the 1-second
  /// auto-flip-back after a non-matching pair is revealed.
  int _flipDelayFramesLeft = 0;

  /// The two face-up cards that haven't been resolved yet.
  final List<int> _pendingFaceUp = <int>[];

  void Function(int score)? _onGameEnd;

  void attachEndCallback(void Function(int score) cb) {
    _onGameEnd = cb;
  }

  // ---------------------------------------------------------------------
  // Lifecycle.
  // ---------------------------------------------------------------------

  void init() {
    if (!_ticker.isActive) _ticker.start();
  }

  void pause() {
    if (_state.isEnded) return;
    _state = _state.copyWith(isPaused: true);
    _ticker.stop();
    notifyListeners();
  }

  void resume() {
    if (_state.isEnded) return;
    _state = _state.copyWith(isPaused: false);
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  bool get hasEnded => _state.isEnded;

  // ---------------------------------------------------------------------
  // Public accessors.
  // ---------------------------------------------------------------------

  MemoryMatchState get state => _state;
  int get score => logic.scoreFor(_state);

  /// Per-cell cards for the renderer.
  List<MemoryCard> get cards => _state.cards;

  bool isFaceUp(int cardId) => _state.cards[cardId].isFaceUp;
  bool isMatched(int cardId) => _state.cards[cardId].isMatched;

  // ---------------------------------------------------------------------
  // Player input.
  // ---------------------------------------------------------------------

  /// Flip a card. If this is the first card of a turn, just face it up.
  /// If it's the second, schedule a 1-second auto-flip-back if they
  /// don't match, or lock them in if they do.
  void tap(int cardId) {
    if (_state.isPaused || _state.isEnded) return;
    if (_flipDelayFramesLeft > 0) return; // ignore during the delay.

    final before = _state;
    final after = logic.flipCard(before, cardId);
    if (identical(before, after)) return; // no-op flip.
    _state = after;

    // Wait for the second card of the pair.
    final pending = <int>[];
    for (final c in _state.cards) {
      if (c.isFaceUp && !c.isMatched) pending.add(c.id);
    }
    if (pending.length == 2) {
      if (pending[0] != cardId && pending[1] != cardId) {
        // Just flipped the second card — schedule a 1-second delay.
        _pendingFaceUp
          ..clear()
          ..addAll(pending);
      } else {
        // First card of a new pair — no delay yet.
      }
    } else if (pending.length == 1) {
      // First card of a turn — no delay yet.
      _pendingFaceUp.clear();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Tick.
  // ---------------------------------------------------------------------

  Duration _lastTick = Duration.zero;
  Duration _accumulator = Duration.zero;

  void _onTick(Duration elapsed) {
    if (_state.isPaused || _state.isEnded) return;

    final delta = elapsed - _lastTick;
    _lastTick = elapsed;

    // 1-second elapsed-seconds counter.
    _accumulator += delta;
    if (_accumulator >= const Duration(seconds: 1)) {
      _accumulator = Duration.zero;
      _state = logic.tick(_state);
      notifyListeners();
    }

    // Flip-back delay.
    if (_flipDelayFramesLeft > 0) {
      _flipDelayFramesLeft--;
      if (_flipDelayFramesLeft == 0) {
        _resolvePendingPair();
      }
    }
  }

  void _resolvePendingPair() {
    if (_pendingFaceUp.length != 2) return;
    final before = _state;
    final after = logic.evaluatePendingPair(before);
    _state = after;

    // Each pair of flips counts as one move.
    _state = logic.recordMove(_state);

    if (_state.isEnded) {
      _ticker.stop();
      notifyListeners();
      _onGameEnd?.call(logic.scoreFor(_state));
      return;
    }

    _pendingFaceUp.clear();
    notifyListeners();
  }

  /// Schedule the 1-second flip-back delay. Called by the widget after
  /// the second face-up card is shown.
  void scheduleFlipBack() {
    if (_flipDelayFramesLeft > 0) return;
    _flipDelayFramesLeft = 60; // ~1 second at 60fps.
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
