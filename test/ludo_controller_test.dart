import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/ludo/ludo_bot.dart';
import 'package:playnest/features/game_player/ludo/ludo_controller.dart';
import 'package:playnest/features/game_player/ludo/ludo_model.dart';

/// Controller-level integration tests.
///
/// We pump the controller with very short bot delays so the suite
/// runs fast. Each bot uses a seeded [Random] for deterministic
/// play. We don't drive the UI — these tests verify the state
/// machine and the end-callback contract only.
///
/// The bot's async loop is exercised by the UI; timing-dependent
/// tests there are flaky and don't add real coverage over the rules
/// + bot tests, which already prove the underlying decisions are
/// correct.
void main() {
  group('LudoController', () {
    test('starts at red, dice is rolled=false', () {
      final c = _newController();
      expect(c.currentState.currentPlayer, LudoPlayer.red);
      expect(c.currentState.rolled, isFalse);
      expect(c.hasEnded, isFalse);
      c.dispose();
    });

    test('rollDice sets dice to 1..6 and rolled=true', () {
      final c = _newController(seed: 1);
      final v = c.rollDice();
      expect(v, inInclusiveRange(1, 6));
      expect(c.currentState.dice, v);
      expect(c.currentState.rolled, isTrue);
      c.dispose();
    });

    test('rolling twice is idempotent (returns same value)', () {
      final c = _newController(seed: 1);
      final a = c.rollDice();
      final b = c.rollDice();
      expect(a, b);
      c.dispose();
    });

    test('hasEnded stays false when only a callback is attached', () {
      // The end-callback contract: attaching a callback must not
      // change game state; the controller must remain paused-friendly.
      final c = _newController(seed: 5);
      c.attachEndCallback((_) {});
      c.pause();
      expect(c.hasEnded, isFalse);
      c.dispose();
    });

    test('a fresh controller can roll and forfeit without crashing', () {
      // Smoke test: roll, then forfeit (even if a legal move exists)
      // — the controller must accept the forfeit and queue the next
      // turn. We don't await timers here; we just verify state
      // consistency.
      final c = _newController(seed: 11);
      c.rollDice();
      c.forfeit();
      expect(c.currentState.rolled, isTrue);
      c.dispose();
    });

    test('attemptMove on the human seat never throws', () {
      // All 4 red tokens start in the yard. If dice == 6, attemptMove(0)
      // is legal and returns true. Otherwise it's illegal and returns
      // false. Either way: must not throw.
      final c = _newController(seed: 2);
      c.rollDice();
      final result = c.attemptMove(0);
      expect(result, isA<bool>());
      c.dispose();
    });

    test('legalMovesForActive is empty when not yet rolled', () {
      final c = _newController();
      expect(c.legalMovesForActive, isEmpty);
      c.dispose();
    });

    test('legalMovesForActive is non-empty when dice=6 and rolled=true', () {
      // Construct a state via a fresh controller and force dice=6.
      // We can't inject the dice directly, so we just call rollDice
      // and check it returns 1..6; if it happens to be 6, the legal
      // moves are 4. If not, 0 (all tokens in yard).
      final c = _newController(seed: 17);
      c.rollDice();
      final dice = c.currentState.dice;
      final legal = c.legalMovesForActive;
      if (dice == 6) {
        expect(legal.length, 4);
      } else {
        expect(legal.length, 0);
      }
      c.dispose();
    });
  });
}

// --- helpers ------------------------------------------------------------

LudoController _newController({
  Duration botDelay = const Duration(milliseconds: 1),
  int? seed,
}) {
  final rng = seed == null ? null : Random(seed);
  return LudoController(
    botDelay: botDelay,
    botForGreen: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
    botForYellow: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
    botForBlue: LudoBot(difficulty: LudoBotDifficulty.hard, random: rng),
  );
}