import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/ludo/ludo_bot.dart';
import 'package:playnest/features/game_player/ludo/ludo_model.dart';

/// Heuristic bot tests.
///
/// We only assert the four behaviors the controller depends on:
///   1. The bot always returns a legal move when one exists.
///   2. Hard bot prefers a free capture when available.
///   3. Easy bot prefers a safe-square landing when one exists.
///   4. The bot returns null when no legal moves exist (so the
///      controller can forfeit the turn without crashing).
void main() {
  group('LudoBot', () {
    test('always returns a legal move when one exists', () {
      const rules = LudoRules();
      var state = LudoState();
      // Manually pull two red tokens out of the yard so we have path
      // tokens without rolling a six.
      state = _putOnPath(state, LudoPlayer.red, 0, 5);
      state = _putOnPath(state, LudoPlayer.red, 1, 20);

      final bot = LudoBot(difficulty: LudoBotDifficulty.easy);
      final move = bot.pickMove(state: state, player: LudoPlayer.red, dice: 3);
      expect(move, isNotNull);
      final result = rules.tryMove(
        state: state,
        player: LudoPlayer.red,
        tokenIndex: move!.tokenIndex,
        steps: 3,
      );
      expect(result.isLegal, isTrue);
    });

    test('hard bot prefers a free capture over a non-capture advance', () {
      var state = LudoState();

      // Red token 0 sits at path index 20 — rolling 4 puts it on 24
      // (a non-safe square). We place a green opponent token on 24 so
      // rolling 4 is a free capture.
      state = _putOnPath(state, LudoPlayer.red, 0, 20);
      state = _putOnPath(state, LudoPlayer.green, 0, 24);

      // Red token 1 sits at path index 30 — rolling 4 puts it on 34
      // (a safe square, no capture available).
      state = _putOnPath(state, LudoPlayer.red, 1, 30);

      final hard = LudoBot(difficulty: LudoBotDifficulty.hard);
      final pick = hard.pickMove(
        state: state,
        player: LudoPlayer.red,
        dice: 4,
      );
      expect(pick, isNotNull);
      expect(pick!.tokenIndex, 0, reason: 'hard bot should grab the capture');
    });

    test('easy bot prefers a safe landing over a non-safe one', () {
      var state = LudoState();

      // Red token 0 at path 30 — rolling 4 → 34 (safe).
      state = _putOnPath(state, LudoPlayer.red, 0, 30);
      // Red token 1 at path 5  — rolling 4 → 9  (non-safe; 8 is safe).
      state = _putOnPath(state, LudoPlayer.red, 1, 5);

      final easy = LudoBot(difficulty: LudoBotDifficulty.easy);
      final pick = easy.pickMove(
        state: state,
        player: LudoPlayer.red,
        dice: 4,
      );
      expect(pick, isNotNull);
      expect(
        pick!.tokenIndex,
        0,
        reason: 'easy bot should prefer the safe landing at path 34',
      );
    });

    test('returns null when no legal moves exist', () {
      // Fresh state, dice = 3, all four red tokens still in the yard.
      // No 6 was rolled, so nothing can leave the yard, so no move.
      final state = LudoState();

      final bot = LudoBot(difficulty: LudoBotDifficulty.hard);
      final pick = bot.pickMove(
        state: state,
        player: LudoPlayer.red,
        dice: 3,
      );
      expect(pick, isNull);
    });
  });
}

// --- helpers ------------------------------------------------------------

/// Build a state where [player]'s token at [tokenIndex] is sitting on
/// path index [pathIndex] (already out of the yard). All other tokens
/// of that player stay in the yard.
///
/// We clone the tokens list, replace that one entry, and rebuild
/// state via copyWith.
LudoState _putOnPath(
  LudoState state,
  LudoPlayer player,
  int tokenIndex,
  int pathIndex,
) {
  final set = state.players[player.seat];
  final tokens = [...set.tokens];
  tokens[tokenIndex] = LudoPositionPath(pathIndex);
  final newSets = [...state.players];
  newSets[player.seat] = LudoTokenSet(tokens: tokens);
  return state.copyWith(players: newSets);
}