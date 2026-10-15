import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ludo_bot.dart';
import 'ludo_model.dart';

/// Top-level controller for the 4-player Ludo mini-game.
///
/// Owns:
///   - the [LudoState] (pure game state from the rules)
///   - the [LudoBot] instances (one for each AI seat)
///   - the auto-play timer (Future.delayed scheduling bot moves)
///   - the end-of-game callback (assigned by the host module)
///
/// Turn flow for a single player:
///   1. State is at this player with [rolled=false] (or =true after dice).
///   2. UI calls [rollDice] → state updates with a fresh 1..6, [rolled=true].
///   3. UI calls [attemptMove] with a token index → rules.applyMove runs,
///      captures are computed, winner is detected.
///   4. If winner: fire onGameEnd exactly once.
///   5. Else: schedule the next turn via [_advanceTurn], which
///      - checks three-sixes-forfeit,
///      - rolls the die for the next player,
///      - if it's an AI seat, schedules [runBotTurn] after a short delay.
///
/// All callbacks (roll / move / forfeit) are deterministic — the controller
/// never decides the dice value, only the human-facing state transitions
/// around the rules.
class LudoController extends ChangeNotifier {
  LudoController({
    LudoRules? rules,
    LudoBot? botForRed,
    LudoBot? botForGreen,
    LudoBot? botForYellow,
    LudoBot? botForBlue,
    this.humanPlayer = LudoPlayer.red,
    this.botDelay = const Duration(milliseconds: 600),
  }) : rules = rules ?? const LudoRules(),
       _bots = {
         if (humanPlayer != LudoPlayer.red) LudoPlayer.red: botForRed ?? _defaultBot(),
         if (humanPlayer != LudoPlayer.green) LudoPlayer.green: botForGreen ?? _defaultBot(),
         if (humanPlayer != LudoPlayer.yellow) LudoPlayer.yellow: botForYellow ?? _defaultBot(),
         if (humanPlayer != LudoPlayer.blue) LudoPlayer.blue: botForBlue ?? _defaultBot(),
       } {
    state = LudoState(players: _initialPlayers());
    state = state.copyWith(rolled: false, dice: 1);
  }

  static LudoBot _defaultBot() =>
      LudoBot(difficulty: LudoBotDifficulty.hard);

  /// Shared RNG for dice rolls. Tests can pass a seeded [Random] if they
  /// want deterministic dice.
  static final Random _diceRng = Random();

  /// Pure rules engine.
  final LudoRules rules;

  /// Bot for each AI seat. Looked up by [_bots][currentPlayer] when
  /// [runBotTurn] fires.
  final Map<LudoPlayer, LudoBot> _bots;

  /// Which seat the local human plays. The other three seats are bots.
  final LudoPlayer humanPlayer;

  /// Delay before each bot move so the player can watch the bot play.
  final Duration botDelay;

  // ---------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------

  /// Current game state. Mutated only through [applyPure] / [applyOrThrow].
  late LudoState state;

  /// Auto-play timer handle. Cancelled on pause / tearDown.
  Timer? _botTimer;

  /// End-of-game callback. Set by the host via [attachEndCallback].
  void Function(int score)? _onGameEnd;

  /// Whether the end-of-game callback has already fired.
  bool _hasEnded = false;

  // ---------------------------------------------------------------------
  // Public accessors
  // ---------------------------------------------------------------------

  LudoState get currentState => state;

  bool get hasEnded => _hasEnded;

  bool get isHumanTurn => state.currentPlayer == humanPlayer;

  bool get isBotTurn => !isHumanTurn && !hasEnded;

  /// Currently-legal moves for the active player. UI uses this to
  /// highlight legal tap targets.
  List<LudoLegalMove> get legalMovesForActive {
    if (hasEnded) return const [];
    if (!state.rolled) return const [];
    return rules.legalMoves(
      state: state,
      player: state.currentPlayer,
      dice: state.dice,
    );
  }

  /// Whether the active player still has any legal action.
  bool get activePlayerHasAnyMove =>
      !hasEnded &&
      rules.hasLegalMove(
        state: state,
        player: state.currentPlayer,
        dice: state.dice,
      );

  /// Path indices that were captured on the most recent successful
  /// move. Empty when the most recent move did not capture. Used by
  /// the board painter to flash capture sites for ~350 ms.
  Set<int> get lastCapturePathIndices => _lastCapturePathIndices;

  Set<int> _lastCapturePathIndices = const <int>{};

  /// Clears [lastCapturePathIndices]. Called by the UI after it has
  /// shown the capture flash so the painter does not keep drawing
  /// the white overlay on subsequent frames.
  void clearLastCaptures() {
    if (_lastCapturePathIndices.isEmpty) return;
    _lastCapturePathIndices = const <int>{};
  }

  // ---------------------------------------------------------------------
  // Host wiring
  // ---------------------------------------------------------------------

  void attachEndCallback(void Function(int score) cb) {
    _onGameEnd = cb;
  }

  // ---------------------------------------------------------------------
  // Lifecycle — the GameModule host calls these.
  // ---------------------------------------------------------------------

  void init() {
    if (hasEnded) return;
    _scheduleBotIfNeeded();
  }

  void pause() {
    _botTimer?.cancel();
    _botTimer = null;
  }

  void resume() {
    if (hasEnded) return;
    _scheduleBotIfNeeded();
  }

  void tearDown() {
    _botTimer?.cancel();
    _botTimer = null;
    _onGameEnd = null;
  }

  // ---------------------------------------------------------------------
  // Player-facing actions
  // ---------------------------------------------------------------------

  /// Roll the die for the active player. No-op if the die is already
  /// rolled for this turn (idempotent).
  ///
  /// Returns the rolled value 1..6.
  int rollDice() {
    if (hasEnded) return state.dice;
    if (state.rolled) return state.dice;
    final value = 1 + _diceRng.nextInt(6);
    state = state.copyWith(rolled: true, dice: value);
    notifyListeners();

    // Three consecutive sixes = forfeit turn (standard Ludo rule).
    final newConsecutive = value == 6 ? state.consecutiveSixes + 1 : 0;
    if (newConsecutive >= 3) {
      state = state.copyWith(consecutiveSixes: 0);
      _scheduleAdvance(zero: true);
      return value;
    }
    state = state.copyWith(consecutiveSixes: newConsecutive);

    // Rolling a 6 grants a bonus roll — same player rolls again at
    // the end of this turn (handled by [_advanceTurn] checking for 6).
    // If the active player has no legal move, the turn is forfeited.
    if (!activePlayerHasAnyMove) {
      _scheduleAdvance(zero: true);
    }
    return value;
  }

  /// Try to move the token at [tokenIndex] of the current player.
  ///
  /// Returns true if the move was legal and applied, false otherwise.
  /// Illegal taps are silently ignored — the UI prevents them visually
  /// by highlighting only legal targets.
  bool attemptMove(int tokenIndex) {
    if (hasEnded) return false;
    if (!state.rolled) return false;
    if (state.currentPlayer != humanPlayer) return false;

    final result = rules.applyMove(
      state: state,
      player: state.currentPlayer,
      tokenIndex: tokenIndex,
      steps: state.dice,
    );
    if (result.state == state) {
      // No-op — applyMove returned an unchanged state (illegal move).
      return false;
    }
    state = result.state;
    _lastCapturePathIndices = {
      for (final c in result.captures)
        if (c.victimStart is LudoPositionPath) (c.victimStart as LudoPositionPath).pathIndex,
    };
    notifyListeners();

    if (state.winner != null) {
      _fireEnd();
      return true;
    }

    _scheduleAdvance();
    return true;
  }

  /// Forfeit the turn without rolling (used by the UI when the player
  /// can't make any move). Equivalent to rolling a die the player
  /// can't use.
  void forfeit() {
    if (hasEnded) return;
    _scheduleAdvance(zero: true);
  }

  // ---------------------------------------------------------------------
  // Bot dispatch
  // ---------------------------------------------------------------------

  /// Schedule the bot's turn. Called automatically after the human
  /// moves (or when the bot starts the match).
  void _scheduleBotIfNeeded() {
    if (hasEnded) return;
    if (isHumanTurn) return;
    _botTimer?.cancel();
    _botTimer = Timer(botDelay, () {
      if (!hasEnded) _runBotTurn();
    });
  }

  void _runBotTurn() {
    if (hasEnded) return;
    final player = state.currentPlayer;
    final bot = _bots[player];
    if (bot == null) {
      // Shouldn't happen — only human seats skip _bots.
      _scheduleAdvance();
      return;
    }

    // Step 1: roll if not already rolled.
    int dice = state.dice;
    if (!state.rolled) {
      dice = 1 + _diceRng.nextInt(6);
      state = state.copyWith(rolled: true, dice: dice);
      notifyListeners();
    }

    // Three consecutive sixes — forfeit without moving.
    final newConsecutive = dice == 6 ? state.consecutiveSixes + 1 : 0;
    if (newConsecutive >= 3) {
      state = state.copyWith(consecutiveSixes: 0);
      _scheduleAdvance(zero: true);
      return;
    }
    state = state.copyWith(consecutiveSixes: newConsecutive);

    // Step 2: pick a move (or forfeit if none).
    final move = bot.pickMove(state: state, player: player, dice: dice);
    if (move == null) {
      _scheduleAdvance(zero: dice != 6);
      return;
    }

    final result = rules.applyMove(
      state: state,
      player: player,
      tokenIndex: move.tokenIndex,
      steps: dice,
    );
    state = result.state;
    _lastCapturePathIndices = {
      for (final c in result.captures)
        if (c.victimStart is LudoPositionPath) (c.victimStart as LudoPositionPath).pathIndex,
    };
    notifyListeners();

    if (state.winner != null) {
      _fireEnd();
      return;
    }

    // A bot rolling a 6 gets another roll (same player) — schedule
    // with a short beat so the UI can show the move before the
    // next dice roll. Rolling anything else advances the turn.
    if (dice == 6) {
      _botTimer?.cancel();
      _botTimer = Timer(const Duration(milliseconds: 350), () {
        if (!hasEnded) _runBotTurn();
      });
    } else {
      _scheduleAdvance(zero: false);
    }
  }

  // ---------------------------------------------------------------------
  // Turn flow
  // ---------------------------------------------------------------------

  void _scheduleAdvance({bool zero = false}) {
    if (hasEnded) return;
    if (zero) {
      _botTimer?.cancel();
      _botTimer = Timer(botDelay, () {
        if (!hasEnded) _advanceTurn();
      });
    } else {
      // Show the post-move state for one beat, then advance.
      _botTimer?.cancel();
      _botTimer = Timer(const Duration(milliseconds: 350), () {
        if (!hasEnded) _advanceTurn();
      });
    }
  }

  /// Advance to the next player. Honors the three-consecutive-sixes
  /// forfeit, then advances seats clockwise. If the next player is a
  /// bot, [_scheduleBotIfNeeded] will start their turn.
  void _advanceTurn() {
    if (hasEnded) return;
    // Same player rolls again on a 6 (bonus roll); otherwise advance
    // to the next seat clockwise.
    final next = rules.nextPlayer(state.currentPlayer);
    final stillSame = state.dice == 6 && state.consecutiveSixes < 3;
    state = state.copyWith(
      currentPlayer: stillSame ? state.currentPlayer : next,
      rolled: false,
      dice: 1,
    );
    notifyListeners();
    _scheduleBotIfNeeded();
  }

  // ---------------------------------------------------------------------
  // End of game
  // ---------------------------------------------------------------------

  void _fireEnd() {
    if (_hasEnded) return;
    _hasEnded = true;
    _botTimer?.cancel();
    final winner = state.winner!;
    final scored = state.players[winner.seat];
    // Score: every finished token is 25 points (rewards a quick kill),
    // every move the match played gives a small participation bonus,
    // and a +200 win bonus is paid when the local human is the winner
    // (so finishing all four tokens is meaningfully rewarded even on
    // a short game where the participation bonus is small).
    final winnerBonus = winner == humanPlayer ? 200 : 0;
    final score =
        scored.finishedCount * 25 +
            (state.moveCount * 2).clamp(0, 100) +
            winnerBonus;
    _onGameEnd?.call(score);
  }

  // ---------------------------------------------------------------------
  // Initial players builder — every seat starts with 4 tokens in yard.
  // ---------------------------------------------------------------------

  static List<LudoTokenSet> _initialPlayers() =>
      List<LudoTokenSet>.generate(4, (_) => LudoTokenSet(), growable: false);

  @override
  void dispose() {
    _botTimer?.cancel();
    _botTimer = null;
    super.dispose();
  }
}