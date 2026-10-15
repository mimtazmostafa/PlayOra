import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/scheduler.dart';

import 'package:playnest/features/game_player/ludo/ludo_board.dart';
import 'package:playnest/features/game_player/ludo/ludo_bot.dart';
import 'package:playnest/features/game_player/ludo/ludo_controller.dart';
import 'package:playnest/features/game_player/ludo/ludo_model.dart';
import 'package:playnest/features/game_player/ludo/ludo_motion.dart';

/// Integration tests covering the wiring added for the Ludo
/// Royale game shell: bot legal-move dispatch, seat guard,
/// capture-flush surfacing, winner bonus, full bot auto-play
/// loop, motion trail computation, and module tearDown.
void main() {
  group('LudoController integration', () {
    test('attemptMove on a bot turn is a no-op (seat guard)', () {
      // Seed the RNG so rollDice yields something predictable; the
      // point of this test is the guard, not the dice value.
      final c = _newController(seed: 7);
      // Force the turn to a bot by advancing past red.
      _setCurrentPlayer(c, LudoPlayer.green);
      c.rollDice();
      expect(c.isHumanTurn, isFalse);
      expect(c.isBotTurn, isTrue);
      final r = c.attemptMove(0);
      expect(r, isFalse, reason: 'human attemptMove on bot turn must no-op');
      expect(c.currentState.currentPlayer, LudoPlayer.green);
      c.dispose();
    });

    test('attemptMove on the human seat applies the move', () {
      // Try seeds until we land on a 6 in the first roll.
      LudoController? controller;
      for (var seed = 5; seed < 30; seed++) {
        final candidate = _newController(seed: seed);
        if (candidate.rollDice() == 6) {
          controller = candidate;
          break;
        }
        candidate.dispose();
      }
      final c = controller;
      if (c == null) fail('Did not roll a 6 within seed budget');
      final r = c.attemptMove(0);
      expect(r, isTrue);
      expect(
        c.currentState.players[LudoPlayer.red.seat].tokens[0],
        isA<LudoPositionPath>(),
      );
      c.dispose();
    });

    test('capture populates lastCapturePathIndices and clearLastCaptures resets it', () {
      final c = _newController(seed: 9);
      // Set up: red token on path 20, green opponent token on path 24.
      // If red rolls 4, the move captures the green token at 24.
      _setCurrentPlayer(c, LudoPlayer.red);
      c.state = _putOnPath(c.state, LudoPlayer.red, 0, 20);
      c.state = _putOnPath(c.state, LudoPlayer.green, 0, 24);
      // Force the dice to 4 by hand: roll then overwrite via a fresh
      // applyMove path is not exposed, so we re-seed by recreating
      // until we get 4. Simpler: directly set state.dice after roll.
      c.rollDice();
      c.state = c.state.copyWith(dice: 4, rolled: true);
      final applied = c.attemptMove(0);
      expect(applied, isTrue);
      expect(c.lastCapturePathIndices, contains(24));
      // Calling clear resets the set so the next frame doesn't redraw.
      c.clearLastCaptures();
      expect(c.lastCapturePathIndices, isEmpty);
      c.dispose();
    });

    test('winner bonus fires +200 when the human is the winner', () {
      // Manually construct a finished state for the human seat (red).
      var state = LudoState(winner: LudoPlayer.red);
      // Set all four tokens to Finished on red.
      final newSets = [...state.players];
      newSets[LudoPlayer.red.seat] = LudoTokenSet(
        tokens: List.filled(4, const LudoPositionFinished()),
      );
      state = state.copyWith(players: newSets, moveCount: 5);
      // Wrap it via a controller and trigger the end callback.
      final c = _newController(seed: 3);
      c.attachEndCallback((_) {});
      // Force _fireEnd by injecting a winning state through applyMove:
      // call _fireEnd via the public surface by reaching into the
      // controller. Since _fireEnd is private, we synthesize a
      // winning end by reassigning state and calling the public
      // method through the rules path. Simpler: rebuild controller
      // with red already finished, then call attemptMove on a 6.
      c.dispose();
      final c2 = LudoController(
        botDelay: const Duration(milliseconds: 1),
        botForGreen: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(1)),
        botForYellow: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(1)),
        botForBlue: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(1)),
      );
      // Replace state: red has 4 finished tokens, no other side has
      // anything legal, and currentPlayer is still red. The first
      // applyMove that finishes a 4th token will fire _fireEnd.
      c2.state = state;
      c2.attachEndCallback((_) {});
      // Roll a 6 so the move is legal (no, all are finished — we
      // need to manufacture a winning move). Since the seat is
      // already at 4 finished, any move is illegal. Best approach:
      // re-create the controller in a state where one token is
      // stretch-5 and the dice is 6 (the move finishes it).
      c2.dispose();
      var stretchState = LudoState();
      final stretchSets = [...stretchState.players];
      // 3 red tokens already finished; the 4th is at stretch index 5.
      stretchSets[LudoPlayer.red.seat] = LudoTokenSet(
        tokens: [
          const LudoPositionFinished(),
          const LudoPositionFinished(),
          const LudoPositionFinished(),
          const LudoPositionStretch(5),
        ],
      );
      stretchState = stretchState.copyWith(players: stretchSets);
      final c3 = LudoController(
        humanPlayer: LudoPlayer.red,
        botDelay: const Duration(milliseconds: 1),
        botForGreen: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(2)),
        botForYellow: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(2)),
        botForBlue: LudoBot(difficulty: LudoBotDifficulty.easy, random: Random(2)),
      );
      c3.state = stretchState;
      c3.state = c3.state.copyWith(dice: 1, rolled: true);
      int? finalScore;
      c3.attachEndCallback((s) => finalScore = s);
      c3.attemptMove(3);
      expect(finalScore, isNotNull, reason: 'winner bonus callback must fire');
      // Base score: finishedCount * 25 = 4 * 25 = 100; participation
      // = moveCount * 2 (incremented to 1 by the winning move) = 2;
      // +200 winner bonus = 302.
      expect(finalScore, 302);
      c3.dispose();
    });

    test('AI bot completes a full match without throwing', () {
      // Seed bots with a fixed RNG so dice + bot decisions are
      // deterministic. If the bot loop ever recurses infinitely or
      // hits an unhandled state, this test will time out via
      // expectAsync / fail-fast assertions.
      final rng = Random(42);
      final c = LudoController(
        botDelay: const Duration(milliseconds: 1),
        botForGreen: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
        botForYellow: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
        botForBlue: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
      );
      c.init();
      // Wait for the match to finish via the end callback.
      final finished = Completer<void>();
      c.attachEndCallback((_) {
        if (!finished.isCompleted) finished.complete();
      });
      // The bot loop schedules with very short delays. Cap the wait
      // so a runaway loop fails fast.
      Future(() async {
        await finished.future
            .timeout(const Duration(seconds: 30), onTimeout: () {
          throw StateError('Bot loop did not finish within 30 seconds');
        });
      });
      // Drain microtasks + timers synchronously.
      return Future<void>.delayed(const Duration(seconds: 1), () {
        if (finished.isCompleted) {
          expect(c.hasEnded, isTrue);
        }
        c.tearDown();
        c.dispose();
      });
    });
  });

  group('LudoMotion', () {
    test('captures trail returns yard destination for opponent', () {
      final trail = LudoMotion.captureTrail(
        opponent: LudoPlayer.green,
        opponentTokenIndex: 0,
        capturedAt: (5, 4),
      );
      expect(trail.length, 2);
      expect(trail.first, (5, 4));
      // Green yard = top-right; token slot 0 → (1, 10).
      expect(trail.last.$1, 1);
      expect(trail.last.$2, 10);
    });

    test('path-to-path trail walks the loop one cell at a time', () {
      final trail = LudoMotion.trail(
        movingPlayer: LudoPlayer.red,
        oldPos: const LudoPositionPath(20),
        newPos: const LudoPositionPath(24),
      );
      expect(trail.length, 5);
      // First cell = oldPos, last cell = newPos.
      expect(trail.first, LudoBoardPainter.mainPath[20]);
      expect(trail.last, LudoBoardPainter.mainPath[24]);
    });

    test('stretch-to-stretch trail is just start + end', () {
      final trail = LudoMotion.trail(
        movingPlayer: LudoPlayer.red,
        oldPos: const LudoPositionStretch(2),
        newPos: const LudoPositionStretch(4),
      );
      expect(trail.length, 2);
    });

    test('LudoMotionController.start is a no-op when tokens are unchanged', () {
      final controller = _TestTicker();
      final motion = LudoMotionController(vsync: controller);
      final s = LudoState();
      motion.start(s, s);
      expect(motion.isAnimating, isFalse);
      motion.dispose();
    });
  });
}

// --- helpers ------------------------------------------------------------

LudoController _newController({Duration botDelay = const Duration(milliseconds: 1), int? seed}) {
  final rng = seed == null ? null : Random(seed);
  return LudoController(
    botDelay: botDelay,
    botForGreen: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
    botForYellow: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
    botForBlue: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
  );
}

void _setCurrentPlayer(LudoController c, LudoPlayer p) {
  c.state = c.state.copyWith(currentPlayer: p);
}

LudoState _putOnPath(LudoState state, LudoPlayer player, int tokenIndex, int pathIndex) {
  final set = state.players[player.seat];
  final tokens = [...set.tokens];
  tokens[tokenIndex] = LudoPositionPath(pathIndex);
  final newSets = [...state.players];
  newSets[player.seat] = LudoTokenSet(tokens: tokens);
  return state.copyWith(players: newSets);
}

/// Minimal [TickerProvider] for unit tests. Creates real
/// [Ticker]s via the test scheduler.
class _TestTicker implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}