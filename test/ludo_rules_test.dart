import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/ludo/ludo_model.dart';

void main() {
  group('LudoRules.startPathIndex', () {
    test('seat 0/13/26/39 for the four players', () {
      const rules = LudoRules();
      expect(rules.startPathIndex(LudoPlayer.red), 0);
      expect(rules.startPathIndex(LudoPlayer.green), 13);
      expect(rules.startPathIndex(LudoPlayer.yellow), 26);
      expect(rules.startPathIndex(LudoPlayer.blue), 39);
    });
  });

  group('LudoRules.isSafe', () {
    test('the 8 standard star squares are safe', () {
      const rules = LudoRules();
      for (final i in const <int>[0, 8, 13, 21, 26, 34, 39, 47]) {
        expect(rules.isSafePathIndex(i), isTrue, reason: 'path[$i] should be safe');
      }
    });

    test('non-star squares are not safe', () {
      const rules = LudoRules();
      expect(rules.isSafePathIndex(1), isFalse);
      expect(rules.isSafePathIndex(7), isFalse);
      expect(rules.isSafePathIndex(25), isFalse);
    });
  });

  group('LudoRules.tryMove — yard exits', () {
    test('a non-6 cannot pull a token out of the yard', () {
      const rules = LudoRules();
      final state = LudoState();
      for (final d in const <int>[1, 2, 3, 4, 5]) {
        final r = rules.tryMove(
          state: state,
          player: LudoPlayer.red,
          tokenIndex: 0,
          steps: d,
        );
        expect(r.isLegal, isFalse, reason: 'steps=$d should be illegal');
        expect(r.reason, LudoIllegalReason.needSixToLeaveYard);
      }
    });

    test('a 6 places the token on the player start path cell', () {
      const rules = LudoRules();
      final state = LudoState();
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.green,
        tokenIndex: 2,
        steps: 6,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionPath(13));
    });
  });

  group('LudoRules.tryMove — main path', () {
    test('a plain forward step wraps around the 52-cell loop', () {
      const rules = LudoRules();
      // Red at path 4 + 3 → path 7 (a plain forward step, well away
      // from the home-entry cell so no diversion). We deliberately
      // don't test "50 + small step" here because red's home-entry
      // is path 51, so anything within 6 steps of 51 diverts into
      // the stretch instead of wrapping.
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(4),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 3,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionPath(7));
    });

    test('rolling past the home-entry cell diverts into the stretch', () {
      const rules = LudoRules();
      // Red's home-entry is path 51. From path 50, distance=1.
      // steps=4 → overshoot = 4 - 1 - 1 = 2 → stretch(2).
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(50),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 4,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionStretch(2));
    });

    test('overshooting the entire stretch from the path is illegal', () {
      const rules = LudoRules();
      // Red's home-entry is path 51. From path 50, distance=1.
      // steps=8 → overshoot = 8 - 1 - 1 = 6 → stretch(6) which is
      // out of bounds → illegal. (tryMove models arbitrary movement
      // for the bot, even though real dice cap at 6.)
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(50),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 9,
      );
      expect(r.isLegal, isFalse);
      expect(r.reason, LudoIllegalReason.overshootsHome);
    });

    test('landing exactly on the home-entry cell diverts to stretch[0]',
        () {
      const rules = LudoRules();
      // Red's home-entry path index is (0 - 1 + 52) % 52 = 51.
      // Start at path(45) and roll 6 → 51 (entry) → stretch(0).
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(45),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 6,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionStretch(0));
    });
  });

  group('LudoRules.tryMove — home stretch', () {
    test('advancing inside the stretch is legal', () {
      const rules = LudoRules();
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionStretch(2),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 3,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionStretch(5));
    });

    test('running 6 from stretch(0) lands in the home triangle', () {
      const rules = LudoRules();
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionStretch(0),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 6,
      );
      expect(r.isLegal, isTrue);
      expect(r.next, const LudoPositionFinished());
    });

    test('overshooting home is illegal', () {
      const rules = LudoRules();
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionStretch(4),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final r = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 3,
      );
      expect(r.isLegal, isFalse);
      expect(r.reason, LudoIllegalReason.overshootsHome);
    });
  });

  group('LudoRules.applyMove — captures', () {
    test('landing on an opponent on a non-safe square sends them home',
        () {
      const rules = LudoRules();
      // Red is on path 12. Rolls 6 → path 18 (a non-safe square).
      // Blue sits on path 18 → gets captured back home.
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(12),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(tokens: const [
          LudoPositionPath(18),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
      ]);
      final result = rules.applyMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 6,
      );
      expect(result.state.players[LudoPlayer.blue.seat].tokens[0],
          const LudoPositionHome());
      expect(result.captures, hasLength(1));
      expect(result.captures.first.victim, LudoPlayer.blue);
    });

    test('landing on a safe square does NOT capture an opponent', () {
      const rules = LudoRules();
      // Red is on path 0 (a safe square by virtue of being its own
      // start). Rolls 6 → path 6 — wait, that's not on green. Reset:
      // Red on path 2, rolls 6 → path 8 (a safe square). Green is
      // parked on path 8. Red's roll should not capture.
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(2),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(tokens: const [
          LudoPositionPath(8),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final result = rules.applyMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 0,
        steps: 6,
      );
      expect(result.captures, isEmpty);
      expect(
        result.state.players[LudoPlayer.green.seat].tokens[0],
        const LudoPositionPath(8),
      );
    });
  });

  group('LudoRules.applyMove — win detection', () {
    test('finishing the fourth token sets the winner', () {
      const rules = LudoRules();
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionFinished(),
          LudoPositionFinished(),
          LudoPositionFinished(),
          LudoPositionStretch(0),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final result = rules.applyMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: 3,
        steps: 6,
      );
      expect(result.state.winner, LudoPlayer.red);
    });
  });

  group('LudoRules.legalMoves', () {
    test('four tokens in the yard, dice=6 → all four are legal', () {
      const rules = LudoRules();
      final state = LudoState();
      final moves = rules.legalMoves(
        state: state,
        player: LudoPlayer.red,
        dice: 6,
      );
      expect(moves, hasLength(4));
    });

    test('four tokens in the yard, dice=3 → no legal moves', () {
      const rules = LudoRules();
      final state = LudoState();
      final moves = rules.legalMoves(
        state: state,
        player: LudoPlayer.red,
        dice: 3,
      );
      expect(moves, isEmpty);
    });

    test('one token near home with steps that overshoot → diverts into stretch',
        () {
      const rules = LudoRules();
      // Red's home-entry is path 51. From path 49, distance to entry
      // is 2. Rolling 3 → overshoot = 3 - 2 - 1 = 0 → stretch(0).
      final state = LudoState(players: [
        LudoTokenSet(tokens: const [
          LudoPositionPath(49),
          LudoPositionHome(),
          LudoPositionHome(),
          LudoPositionHome(),
        ]),
        LudoTokenSet(),
        LudoTokenSet(),
        LudoTokenSet(),
      ]);
      final moves = rules.legalMoves(
        state: state,
        player: LudoPlayer.red,
        dice: 3,
      );
      expect(moves, hasLength(1));
      expect(moves.first.next, const LudoPositionStretch(0));
    });
  });

  group('LudoRules turn flow', () {
    test('three consecutive sixes forfeit the turn', () {
      const rules = LudoRules();
      expect(rules.threeSixesForfeit(0), isFalse);
      expect(rules.threeSixesForfeit(1), isFalse);
      expect(rules.threeSixesForfeit(2), isTrue);
      expect(rules.threeSixesForfeit(3), isTrue);
    });

    test('nextPlayer walks clockwise seats', () {
      const rules = LudoRules();
      expect(rules.nextPlayer(LudoPlayer.red), LudoPlayer.green);
      expect(rules.nextPlayer(LudoPlayer.green), LudoPlayer.yellow);
      expect(rules.nextPlayer(LudoPlayer.yellow), LudoPlayer.blue);
      expect(rules.nextPlayer(LudoPlayer.blue), LudoPlayer.red);
    });
  });
}