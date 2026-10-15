import 'dart:math';

import 'ludo_model.dart';

/// Picks the best move for a bot player given a dice roll.
///
/// This is intentionally a single heuristic with two difficulty tunings
/// rather than a search-based AI. The goal is "plays a reasonable game
/// without taking a week to write". For a v1.0 shipping product in
/// Bangladesh, an opponent that mostly advances toward home and takes
/// free captures is exactly the right bar.
///
/// ## Scoring (higher = better)
///
///   +1000 per token that has finished                       (dominant)
///   +150 per stretch index step (the closer to home, the better)
///   +50  for any move that enters the stretch
///   +25  per captured opponent (free capture beats non-capture)
///   +30  if the move lands on a safe square                 (easy only)
///   −40  if the move would land on a cell already occupied
///         by a teammate (clustering penalty)
///   −20  if the move lands on a non-safe cell AND an opponent
///         is within 6 path steps of the landing cell       (hard risk)
///
/// Difficulty only flips the safe-cell bonus and the risk penalty —
/// the rest of the heuristic is identical so easy and hard bots play
/// the same average game, just with different shading.
class LudoBot {
  LudoBot({required this.difficulty, Random? random})
      : _random = random ?? Random();

  final LudoBotDifficulty difficulty;
  final Random _random;

  /// Picks the best move for [player] given [state] and the current
  /// [dice]. Returns null when no legal move exists (the controller
  /// treats that as "forfeit the turn").
  LudoLegalMove? pickMove({
    required LudoState state,
    required LudoPlayer player,
    required int dice,
  }) {
    const rules = LudoRules();
    final moves = rules.legalMoves(
      state: state,
      player: player,
      dice: dice,
    );
    if (moves.isEmpty) return null;

    final scored = <(LudoLegalMove, double)>[];
    for (final move in moves) {
      final score = _scoreMove(
        state: state,
        player: player,
        dice: dice,
        move: move,
      );
      scored.add((move, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // Ties: in easy mode keep the lowest-index token (deterministic,
    // predictable). In hard mode add a small jitter so the same
    // board + dice doesn't always produce the same move — keeps the
    // player from "reading" the bot after a few matches.
    final top = scored.first.$2;
    final leaders = scored.where((s) => (s.$2 - top).abs() < 0.0001).toList();
    if (difficulty == LudoBotDifficulty.hard && leaders.length > 1) {
      final pick = _random.nextInt(leaders.length);
      return leaders[pick].$1;
    }
    return leaders.first.$1;
  }

  double _scoreMove({
    required LudoState state,
    required LudoPlayer player,
    required int dice,
    required LudoLegalMove move,
  }) {
    final rules = const LudoRules();
    final tokens = state.players[player.seat].tokens;
    final next = move.next;

    // Simulate the move against a hypothetical state so we can score
    // "after the move" — captures, safe squares, teammates.
    final simulated = rules.applyMove(
      state: state,
      player: player,
      tokenIndex: move.tokenIndex,
      steps: dice,
    );
    final captures = simulated.captures.length;

    // Count the new "finished" tokens after this move.
    final newFinished = simulated.state.players[player.seat].finishedCount;
    final currentFinished = tokens.whereType<LudoPositionFinished>().length;
    final finishedGain = newFinished - currentFinished;

    double score = 0;

    // 1. Winning is everything.
    score += 1000 * finishedGain;

    // 2. Stretch progress — being deep in the stretch is much safer
    //    than being on the shared loop.
    if (next is LudoPositionStretch) {
      score += 50; // entered the stretch
      score += 150 * next.stretchIndex; // deeper = better
    }

    // 3. Captures — only count if the move is actually on the main
    //    path (captures are reported only for path landings).
    if (next is LudoPositionPath) {
      score += 25 * captures;

      // 4. Safe-square bonus: easy bots love safe squares.
      if (rules.isSafePathIndex(next.pathIndex)) {
        if (difficulty == LudoBotDifficulty.easy) {
          score += 30;
        }
      } else if (difficulty == LudoBotDifficulty.hard) {
        // 5. Risk penalty: hard bots avoid non-safe squares when an
        //    opponent is within 6 steps.
        if (_opponentThreatRange(
              state: state,
              player: player,
              landingIndex: next.pathIndex,
            ) !=
            null) {
          score -= 20;
        }
      }

      // 6. Clustering penalty: if a teammate is already on the
      //    landing cell (which is impossible — same player can't
      //    share a path cell per Ludo rules, but we guard against
      //    future bugs), avoid stacking.
      for (final other in tokens) {
        if (other is LudoPositionPath &&
            other.pathIndex == next.pathIndex &&
            other != tokens[move.tokenIndex]) {
          score -= 40;
        }
      }
    }

    // 7. Tiny jitter in hard mode so two equally-good moves don't
    //    always pick the same token.
    if (difficulty == LudoBotDifficulty.hard) {
      score += _random.nextDouble() * 0.5;
    }

    return score;
  }

  /// Returns the [LudoPlayer] of an opponent whose next dice roll
  /// could land on [landingIndex] within 6 steps; null if none.
  ///
  /// Used by the risk penalty — a hard bot doesn't want to drop a
  /// token on a non-safe square if an opponent is hot on its tail.
  LudoPlayer? _opponentThreatRange({
    required LudoState state,
    required LudoPlayer player,
    required int landingIndex,
  }) {
    for (final other in LudoPlayer.values) {
      if (other == player) continue;
      for (final t in state.players[other.seat].tokens) {
        if (t is! LudoPositionPath) continue;
        // Distance from t to landingIndex, in the opponent's forward
        // direction. If a 1..6 roll from t would land on
        // landingIndex, t is a threat.
        final toLanding =
            (landingIndex - t.pathIndex + kMainPathLength) % kMainPathLength;
        if (toLanding >= 1 && toLanding <= 6) {
          return other;
        }
      }
    }
    return null;
  }
}