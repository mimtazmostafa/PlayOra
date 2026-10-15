/// Pure-Dart Ludo game model. No Flutter imports — this file is the
/// single source of truth for board state, movement rules, capture,
/// and win conditions. Everything else (controller, UI, AI) reads
/// from here.
///
/// ## Board geometry
///
/// The standard Ludo board is a 15×15 grid with a cross-shaped track
/// of 52 outer cells (the "main path") plus 4 colored home columns
/// of 6 cells each. Each player owns 4 tokens that start in their
/// home yard (off-board), enter the main path on a 6, and try to
/// reach the center triangle ("home").
///
/// ### Main path
///
/// The 52-cell loop is indexed 0..51. Each player has a personal
/// "start" cell, which is the cell *just after* their yard exit:
///
///   - Red    → starts at path index 0
///   - Green  → starts at path index 13
///   - Yellow → starts at path index 26
///   - Blue   → starts at path index 39
///
/// On the standard board these four cells are the 8-star "safe
/// squares" (the player's own start + the star three squares before
/// the next player's start). The four 8-star cells are at path
/// indices: 0, 8, 13, 21, 26, 34, 39, 47.
///
/// ### Home stretch
///
/// When a token completes a full lap and lands on the cell *just
/// before* its yard exit (i.e. one step before its own start cell,
/// which is path index `(start - 1) mod 52`), it diverts into the
/// 6-cell colored "home stretch" instead of looping again. From
/// there it needs exactly 6 more steps to reach the final triangle.
///
/// ## Token position encoding
///
/// We use a tagged enum so every legal transition is a single
/// function call and every illegal move is representable (so the
/// controller can gray out illegal buttons without silently no-op'ing).
library;

/// Number of cells on the main 52-cell loop.
const int kMainPathLength = 52;

/// Number of cells in each player's home stretch (after the last
/// path cell, before the final triangle).
const int kHomeStretchLength = 6;

/// Safe square offsets around the loop. These are the 8 starred cells
/// on the standard board; tokens on safe squares cannot be captured.
///
/// Derived from the standard layout:
///
///   red start   = 0,    green start = 13,   yellow start = 26,  blue start = 39
///   stars at    = 0, 8, 13, 21, 26, 34, 39, 47
const Set<int> kSafePathIndices = <int>{0, 8, 13, 21, 26, 34, 39, 47};

/// One of the four players. The integer value doubles as the offset
/// into the main 52-cell loop (in path-cell units), and identifies
/// which colored home stretch a token is heading toward.
enum LudoPlayer {
  red(0, 'Red'),
  green(1, 'Green'),
  yellow(2, 'Yellow'),
  blue(3, 'Blue');

  const LudoPlayer(this.seat, this.label);

  /// 0..3 — used to index per-player arrays and as the path offset.
  final int seat;

  /// Display label for the UI ("Red", "Green", etc.).
  final String label;
}

/// Where a single token currently sits. We model the token's
/// location as a tagged state so the UI can render the yard, the
/// main loop, the home stretch, and the finished pile without
/// inventing magic numbers.
sealed class LudoPosition {
  const LudoPosition();

  /// Pretty-print for the test harness + debug overlay.
  @override
  String toString();

  @override
  bool operator ==(Object other);

  @override
  int get hashCode;
}

/// Token is parked in its home yard and cannot move until the player
/// rolls a 6. Index is the yard slot (0..3) — purely cosmetic, used
/// by the UI to position the four yard markers.
class LudoPositionHome extends LudoPosition {
  const LudoPositionHome({this.yardSlot = 0});

  final int yardSlot;

  @override
  String toString() => 'home[$yardSlot]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LudoPositionHome && other.yardSlot == yardSlot);

  @override
  int get hashCode => Object.hash('home', yardSlot);
}

/// Token is on the main 52-cell loop. [pathIndex] is 0..51.
class LudoPositionPath extends LudoPosition {
  const LudoPositionPath(this.pathIndex);

  final int pathIndex;

  @override
  String toString() => 'path[$pathIndex]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LudoPositionPath && other.pathIndex == pathIndex);

  @override
  int get hashCode => Object.hash('path', pathIndex);
}

/// Token is in the player's colored home stretch (the 6 cells
/// leading to the center triangle). [stretchIndex] is 0..5 where 0
/// is the cell just after the path entry and 5 is the last cell
/// before the final triangle.
class LudoPositionStretch extends LudoPosition {
  const LudoPositionStretch(this.stretchIndex);

  final int stretchIndex;

  @override
  String toString() => 'stretch[$stretchIndex]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LudoPositionStretch && other.stretchIndex == stretchIndex);

  @override
  int get hashCode => Object.hash('stretch', stretchIndex);
}

/// Token has reached the center triangle — the player has finished
/// this piece.
class LudoPositionFinished extends LudoPosition {
  const LudoPositionFinished();

  @override
  String toString() => 'finished';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LudoPositionFinished;

  @override
  int get hashCode => 'finished'.hashCode;
}

/// Difficulty for the bot AI. A single heuristic is reused; the knob
/// just changes the bias between "advance safely" and "capture
/// aggressively".
enum LudoBotDifficulty {
  /// Plays it safe: prefers home-stretch, captures only when free.
  easy,

  /// Aggressive: prefers captures, will take small risks to break
  /// up clusters, still aims to finish.
  hard,
}

/// One player's view of their four tokens.
class LudoTokenSet {
  LudoTokenSet({List<LudoPosition>? tokens})
      : tokens = tokens ??
            List<LudoPosition>.filled(
              4,
              const LudoPositionHome(),
              growable: false,
            );

  /// Exactly four positions — one per token. Index is the token id.
  final List<LudoPosition> tokens;

  /// Returns the number of tokens that have finished.
  int get finishedCount =>
      tokens.whereType<LudoPositionFinished>().length;

  /// Returns true when every token has finished — i.e. the player
  /// has won the match.
  bool get hasWon => finishedCount == 4;

  /// Returns the indices of every token currently in the home yard.
  /// (These are the only ones a player can pull out on a 6.)
  List<int> get homeIndices {
    final out = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] is LudoPositionHome) out.add(i);
    }
    return out;
  }

  /// Returns the indices of every token currently on the main path.
  List<int> get pathIndices {
    final out = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] is LudoPositionPath) out.add(i);
    }
    return out;
  }

  /// Returns the indices of every token in the home stretch.
  List<int> get stretchIndices {
    final out = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] is LudoPositionStretch) out.add(i);
    }
    return out;
  }

  /// Returns true when no token has moved yet — used by the UI to
  /// distinguish "fresh game" from "mid-game resumption".
  bool get isAtStart =>
      tokens.every((p) => p is LudoPositionHome && p.yardSlot == 0);

  /// Immutable setter for tests + the bot. Returns a new
  /// [LudoTokenSet] with the token at [index] replaced by [next].
  LudoTokenSet setToken(int index, LudoPosition next) {
    final copy = List<LudoPosition>.of(tokens);
    copy[index] = next;
    return LudoTokenSet(tokens: copy);
  }
}

/// The full game state at a single point in time.
class LudoState {
  LudoState({
    List<LudoTokenSet>? players,
    this.currentPlayer = LudoPlayer.red,
    this.consecutiveSixes = 0,
    this.dice = 1,
    this.rolled = false,
    this.winner,
    this.moveCount = 0,
  }) : players = players ?? _initialPlayers();

  /// Four token-sets, indexed by [LudoPlayer.seat].
  final List<LudoTokenSet> players;

  /// Whose turn it is right now.
  final LudoPlayer currentPlayer;

  /// Number of consecutive 6s the current player has rolled. Three
  /// in a row forfeits the turn (standard house rule).
  final int consecutiveSixes;

  /// The current dice value (1..6). Meaningless until [rolled] is
  /// true.
  final int dice;

  /// True once the current player has rolled this turn. The bot
  /// only fires after this flips; the UI only enables token taps
  /// after this flips.
  final bool rolled;

  /// Set when somebody has finished all four tokens.
  final LudoPlayer? winner;

  /// Total moves played. Useful for tests + a future "match length"
  /// stat on the post-game rewards screen.
  final int moveCount;

  static List<LudoTokenSet> _initialPlayers() => List<LudoTokenSet>.generate(
        4,
        (_) => LudoTokenSet(),
        growable: false,
      );

  /// Tokens for [player].
  LudoTokenSet tokensOf(LudoPlayer player) => players[player.seat];

  /// Immutable: returns a copy with [updates] applied. Anything
  /// not in [updates] is carried over from `this`.
  LudoState copyWith({
    List<LudoTokenSet>? players,
    LudoPlayer? currentPlayer,
    int? consecutiveSixes,
    int? dice,
    bool? rolled,
    LudoPlayer? winner,
    bool clearWinner = false,
    int? moveCount,
  }) {
    return LudoState(
      players: players ?? this.players,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      dice: dice ?? this.dice,
      rolled: rolled ?? this.rolled,
      winner: clearWinner ? null : (winner ?? this.winner),
      moveCount: moveCount ?? this.moveCount,
    );
  }
}

/// Pure functions for movement and legality. None of these mutate
/// [LudoState] — they describe "what would happen if" so the
/// controller can apply them and so the bot can score candidates.
class LudoRules {
  const LudoRules();

  /// The cell a [player]'s token enters when it leaves the yard.
  /// Red = 0, Green = 13, Yellow = 26, Blue = 39.
  int startPathIndex(LudoPlayer player) =>
      (player.seat * 13) % kMainPathLength;

  /// The path cell a token must reach to divert into the player's
  /// home stretch. It's the cell *just before* the player's start,
  /// which on the standard board is the cell 51 steps after leaving
  /// the yard.
  int homeEntryPathIndex(LudoPlayer player) =>
      (startPathIndex(player) - 1 + kMainPathLength) % kMainPathLength;

  /// True if [pathIndex] is a starred safe square (no capture).
  bool isSafePathIndex(int pathIndex) =>
      kSafePathIndices.contains(pathIndex);

  /// True if a player token currently sitting on [pathIndex] is
  /// immune to capture.
  bool isSafe(LudoPlayer player, int pathIndex) =>
      isSafePathIndex(pathIndex);

  /// Result of attempting to move token [tokenIndex] for
  /// [player] by [steps] (a dice roll, 1..6) from [state].
  ///
  /// Note: this method does NOT assert [steps] is in 1..6 because it
  /// also models "projected" moves for the bot (e.g. "what would
  /// happen if I rolled 4 next"). Callers that pass a real dice roll
  /// (the controller) enforce 1..6 themselves.
  LudoMoveResult tryMove({
    required LudoState state,
    required LudoPlayer player,
    required int tokenIndex,
    required int steps,
  }) {
    final current = state.players[player.seat].tokens[tokenIndex];
    switch (current) {
      case LudoPositionHome():
        if (steps != 6) {
          return const LudoMoveResult.illegal(
            reason: LudoIllegalReason.needSixToLeaveYard,
          );
        }
        return LudoMoveResult.legal(
          next: LudoPositionPath(startPathIndex(player)),
        );
      case LudoPositionPath(:final pathIndex):
        // Steps from the current cell to the home-entry cell along
        // this player's direction. If `steps` is exactly equal to
        // this distance, the token diverts into the stretch at
        // index 0. If `steps` is greater, it overshoots → illegal.
        final toEntry =
            (homeEntryPathIndex(player) - pathIndex + kMainPathLength) %
                kMainPathLength;
        if (steps == toEntry) {
          return LudoMoveResult.legal(
            next: const LudoPositionStretch(0),
          );
        }
        if (steps > toEntry) {
          // Either it overshoots into the stretch (legal but the
          // stretch-index must be small enough) or it overshoots
          // past the stretch into finished (legal — running out
          // exactly is a home run). Anything else is illegal.
          final overshoot = steps - toEntry - 1;
          if (overshoot < 0) {
            // steps == toEntry is handled above; unreachable.
            return const LudoMoveResult.illegal(
              reason: LudoIllegalReason.unknown,
            );
          }
          if (overshoot < kHomeStretchLength) {
            return LudoMoveResult.legal(
              next: LudoPositionStretch(overshoot),
            );
          }
          if (overshoot == kHomeStretchLength) {
            return LudoMoveResult.legal(next: const LudoPositionFinished());
          }
          return const LudoMoveResult.illegal(
            reason: LudoIllegalReason.overshootsHome,
          );
        }
        // Plain forward step on the main loop.
        return LudoMoveResult.legal(
          next: LudoPositionPath((pathIndex + steps) % kMainPathLength),
        );
      case LudoPositionStretch(:final stretchIndex):
        final nextIndex = stretchIndex + steps;
        if (nextIndex < kHomeStretchLength) {
          return LudoMoveResult.legal(
            next: LudoPositionStretch(nextIndex),
          );
        }
        if (nextIndex == kHomeStretchLength) {
          return LudoMoveResult.legal(next: const LudoPositionFinished());
        }
        return const LudoMoveResult.illegal(
          reason: LudoIllegalReason.overshootsHome,
        );
      case LudoPositionFinished():
        return const LudoMoveResult.illegal(
          reason: LudoIllegalReason.alreadyHome,
        );
    }
  }

  /// Returns the index of the path cell that a token currently at
  /// [pos] will land on if moved by [steps]. Returns null if the
  /// token isn't on the main path (yard / stretch / finished).
  ///
  /// Used by [resolveCapture] to ask "if I move here, does it land
  /// on an enemy token?".
  static int? landingPathIndex({
    required LudoPosition pos,
    required LudoPlayer owner,
    required int steps,
  }) {
    if (pos is! LudoPositionPath) return null;
    final start = (owner.seat * 13) % kMainPathLength;
    final homeEntry =
        (start - 1 + kMainPathLength) % kMainPathLength;
    final toEntry = (homeEntry - pos.pathIndex + kMainPathLength) %
        kMainPathLength;
    if (steps == toEntry) {
      // Diverts into stretch — no capture possible on the stretch.
      return null;
    }
    if (steps > toEntry) {
      // Either enters stretch or finishes; no path capture possible.
      return null;
    }
    return (pos.pathIndex + steps) % kMainPathLength;
  }

  /// Applies a legal move and returns the new state + a list of
  /// opponent tokens that were captured (so the UI can flash them
  /// home). This is the single mutation function in the file —
  /// everything else is a pure projection.
  LudoApplyResult applyMove({
    required LudoState state,
    required LudoPlayer player,
    required int tokenIndex,
    required int steps,
  }) {
    assert(steps >= 1 && steps <= 6, 'dice must be 1..6, got $steps');
    final move = tryMove(
      state: state,
      player: player,
      tokenIndex: tokenIndex,
      steps: steps,
    );
    if (!move.isLegal || move.next == null) {
      return LudoApplyResult(state: state, captures: const []);
    }
    final newTokens = state.players[player.seat].setToken(
      tokenIndex,
      move.next!,
    );
    final updatedPlayers = List<LudoTokenSet>.of(state.players);
    updatedPlayers[player.seat] = newTokens;
    final captures = <LudoCapture>[];

    // Capture pass — check if the token's new position is on the main
    // path (only path tokens can be captured; stretch + finished are
    // safe by virtue of being off the shared loop).
    if (move.next is LudoPositionPath) {
      final landedAt = (move.next as LudoPositionPath).pathIndex;
      // The player's own start cell is a safe square.
      if (!isSafePathIndex(landedAt)) {
        for (final other in LudoPlayer.values) {
          if (other == player) continue;
          final otherTokens = state.players[other.seat];
          for (var i = 0; i < otherTokens.tokens.length; i++) {
            final p = otherTokens.tokens[i];
            if (p is LudoPositionPath && p.pathIndex == landedAt) {
              // Capture! Send the opponent token home.
              final updatedOther = otherTokens.setToken(
                i,
                const LudoPositionHome(),
              );
              updatedPlayers[other.seat] = updatedOther;
              captures.add(
                LudoCapture(
                  victim: other,
                  tokenIndex: i,
                  victimStart: p,
                ),
              );
            }
          }
        }
      }
    }

    final next = state.copyWith(
      players: updatedPlayers,
      moveCount: state.moveCount + 1,
    );

    // Win check: did this player just finish all four tokens?
    final newSet = updatedPlayers[player.seat];
    if (newSet.hasWon) {
      return LudoApplyResult(
        state: next.copyWith(
          winner: player,
          rolled: false,
        ),
        captures: captures,
      );
    }

    return LudoApplyResult(state: next, captures: captures);
  }

  /// Returns the next [LudoPlayer] in clockwise seat order.
  LudoPlayer nextPlayer(LudoPlayer current) {
    final nextSeat = (current.seat + 1) % LudoPlayer.values.length;
    return LudoPlayer.values[nextSeat];
  }

  /// Returns every legal (tokenIndex, nextPosition) pair for
  /// [player] given a [dice] roll from [state]. Used by the UI to
  /// highlight movable tokens and by the bot to score candidates.
  List<LudoLegalMove> legalMoves({
    required LudoState state,
    required LudoPlayer player,
    required int dice,
  }) {
    final out = <LudoLegalMove>[];
    final tokens = state.players[player.seat].tokens;
    for (var i = 0; i < tokens.length; i++) {
      final r = tryMove(
        state: state,
        player: player,
        tokenIndex: i,
        steps: dice,
      );
      if (r.isLegal && r.next != null) {
        out.add(LudoLegalMove(tokenIndex: i, next: r.next!));
      }
    }
    return out;
  }

  /// Convenience: true when [player] has at least one legal move
  /// for the current dice. When false, the turn is forfeit (the
  /// controller hands off to the next player).
  bool hasLegalMove({
    required LudoState state,
    required LudoPlayer player,
    required int dice,
  }) =>
      legalMoves(state: state, player: player, dice: dice).isNotEmpty;

  /// True if rolling another six would forfeit the turn (three in
  /// a row is the standard house rule).
  bool threeSixesForfeit(int consecutiveSixes) => consecutiveSixes >= 2;
}

/// Result of attempting a move — lets the UI distinguish "you
/// tapped a token that can't move" from "you tapped a token that
/// moved normally".
class LudoMoveResult {
  const LudoMoveResult.legal({required this.next})
      : isLegal = true,
        reason = LudoIllegalReason.none,
        captures = const [];

  const LudoMoveResult.illegal({required this.reason})
      : isLegal = false,
        next = null,
        captures = const [];

  final bool isLegal;

  /// Where the token would land. Null when illegal.
  final LudoPosition? next;

  final LudoIllegalReason reason;

  /// Capture list — only populated by [LudoRules.applyMove], not by
  /// [LudoRules.tryMove] (tryMove doesn't know about opponents).
  final List<LudoCapture> captures;
}

/// Why a move is illegal — surfaces a specific string for the UI to
/// show ("You need a 6 to leave the yard", "Overshoots home").
enum LudoIllegalReason {
  none,
  needSixToLeaveYard,
  overshootsHome,
  alreadyHome,
  unknown,
}

/// Result of applying a move — bundles the new state with the
/// captures so the UI can animate them.
class LudoApplyResult {
  const LudoApplyResult({required this.state, required this.captures});

  final LudoState state;
  final List<LudoCapture> captures;
}

/// One opponent token that got sent back to its yard.
class LudoCapture {
  const LudoCapture({
    required this.victim,
    required this.tokenIndex,
    required this.victimStart,
  });

  final LudoPlayer victim;
  final int tokenIndex;
  final LudoPosition victimStart;
}

/// One legal (tokenIndex → nextPosition) move, used by both the UI
/// highlight layer and the bot scorer.
class LudoLegalMove {
  const LudoLegalMove({required this.tokenIndex, required this.next});

  final int tokenIndex;
  final LudoPosition next;
}