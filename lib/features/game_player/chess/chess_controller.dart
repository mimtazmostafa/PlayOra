import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chess_model.dart';

/// Difficulty enum for the chess bot. Each maps to a fixed max-depth
/// ceiling on a stock alpha-beta search — same engine, different cap.
enum ChessBotDifficulty { easy, medium, hard }

PieceColor _other(PieceColor c) =>
    c == PieceColor.white ? PieceColor.black : PieceColor.white;

extension ChessBotDifficultyX on ChessBotDifficulty {
  int get searchDepth {
    switch (this) {
      case ChessBotDifficulty.easy:
        return 1;
      case ChessBotDifficulty.medium:
        return 2;
      case ChessBotDifficulty.hard:
        return 3;
    }
  }
}

/// High-level chess controller — owns the [ChessState], drives the
/// bot's moves, and exposes a change-notifier surface for the UI.
///
/// Lifecycle (mirror of [LudoController]):
///   - [init] starts the bot's first move if white isn't the human.
///   - [pause] / [resume] cancel / re-schedule the bot timer.
///   - [tearDown] disposes timers and the end callback.
///   - [attemptMove] is the only entry point for human input — it
///     refuses anything not in the legal-moves list and only acts
///     on [state.sideToMove] == [humanColor].
class ChessController extends ChangeNotifier {
  ChessController({
    ChessRules? rules,
    ChessEngine? engine,
    ChessBotDifficulty difficulty = ChessBotDifficulty.medium,
    this.humanColor = PieceColor.white,
    this.botDelay = const Duration(milliseconds: 500),
  })  : rules = rules ?? const ChessRules(),
        _engine = engine ?? ChessEngine(maxDepth: difficulty.searchDepth) {
    state = ChessState();
  }

  final ChessRules rules;
  ChessEngine _engine;
  final PieceColor humanColor;
  final Duration botDelay;

  late ChessState state;

  Timer? _botTimer;
  bool _hasEnded = false;

  /// Sound hook stub: fires after a piece is captured (board shake /
  /// capture-flash can use this). No audio plugin installed yet.
  void Function(PieceType captured)? onCapture;

  /// Sound hook stub: fires when a pawn promotes.
  void Function(PieceType promotedTo)? onPromote;

  /// Convenience accessors for UI bind-points.
  ChessState get currentState => state;
  bool get hasEnded => _hasEnded;
  bool get isHumanTurn =>
      !_hasEnded && state.sideToMove == humanColor;
  bool get isBotTurn =>
      !_hasEnded && state.sideToMove != humanColor;

  /// Toggle the AI depth mid-game (e.g. difficulty selector). The
  /// engine is recreated so we don't keep the old depth cap around.
  void setDifficulty(ChessBotDifficulty d) {
    _engine = ChessEngine(maxDepth: d.searchDepth);
    if (isBotTurn) _scheduleBot();
  }

  /// Host callback — assigned by the GameModule shim.
  void Function(int score)? _onGameEnd;
  void attachEndCallback(void Function(int score) cb) => _onGameEnd = cb;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  void init() {
    _hasEnded = false;
    _scheduleBot();
  }

  void pause() {
    _botTimer?.cancel();
    _botTimer = null;
  }

  void resume() {
    if (_hasEnded) return;
    _scheduleBot();
  }

  void tearDown() {
    _botTimer?.cancel();
    _botTimer = null;
    _onGameEnd = null;
    onCapture = null;
    onPromote = null;
  }

  // ---------------------------------------------------------------------
  // Move input
  // ---------------------------------------------------------------------

  /// Returns true if the move was legal and applied. Illegal attempts
  /// return false silently so the UI can ignore them.
  bool attemptMove(ChessMove move) {
    if (_hasEnded) return false;
    if (state.sideToMove != humanColor) return false;
    final legal = rules.legalMoves(state);
    final matched = legal.firstWhere(
      (m) => m.from == move.from && m.to == move.to && m.promotion == move.promotion,
      orElse: () => const ChessMove(from: 0, to: 0),
    );
    if (matched.from == 0 && matched.to == 0) return false;

    final captured = state.board[move.to];
    final wasEnPassant = matched.enPassant;
    final wasCapture = matched.capture || wasEnPassant;

    final result = rules.applyMove(state, matched);
    state = result.next;
    notifyListeners();

    if (wasCapture && captured != 0) {
      // En-passant captures "empty" the destination board slot, but
      // there's still a pawn on the captured-by-ep square.
      onCapture?.call(pieceType(wasEnPassant
          ? encode(_other(humanColor), PieceType.pawn)
          : captured));
    } else if (wasEnPassant) {
      onCapture?.call(PieceType.pawn);
    }
    if (matched.promotion != null) {
      onPromote?.call(matched.promotion!);
    }

    _advanceFromEnd();
    return true;
  }

  /// Convenience: snap back to a fresh game. Used by the "Play again"
  /// hook on the end modal — actually the modal rebuilds a new
  /// controller, but expose this for tests.
  void restart() {
    pause();
    state = ChessState();
    _hasEnded = false;
    notifyListeners();
    _scheduleBot();
  }

  // ---------------------------------------------------------------------
  // Bot turn
  // ---------------------------------------------------------------------

  void _scheduleBot() {
    if (_hasEnded) return;
    if (state.sideToMove == humanColor) return;
    _botTimer?.cancel();
    _botTimer = Timer(botDelay, () {
      if (!_hasEnded && state.sideToMove != humanColor) {
        _runBotTurn();
      }
    });
  }

  void _runBotTurn() {
    if (_hasEnded) return;
    final move = _engine.pickMove(state);
    if (move == null) {
      // Engine found no legal move — likely the human just mated the
      // AI. Status will already reflect that. Let _advanceFromEnd
      // handle end-of-game.
      _advanceFromEnd();
      return;
    }
    final captured = state.board[move.to];
    final wasEnPassant = move.enPassant;
    final wasCapture = move.capture || wasEnPassant;
    final result = rules.applyMove(state, move);
    state = result.next;
    notifyListeners();
    if (wasCapture && captured != 0) {
      onCapture?.call(pieceType(wasEnPassant
          ? encode(humanColor, PieceType.pawn)
          : captured));
    } else if (wasEnPassant) {
      onCapture?.call(PieceType.pawn);
    }
    if (move.promotion != null) {
      onPromote?.call(move.promotion!);
    }
    _advanceFromEnd();
  }

  /// Shared endgame path: if the state is terminal, fire the end
  /// callback exactly once; otherwise let the bot pick up on its
  /// turn.
  void _advanceFromEnd() {
    if (state.status != ChessGameStatus.ongoing) {
      _fireEnd();
      return;
    }
    _scheduleBot();
  }

  void _fireEnd() {
    if (_hasEnded) return;
    _hasEnded = true;
    _botTimer?.cancel();

    // Score formula:
    //   +300 human win (checkmate where human mates the bot).
    //   +150 draw (any draw the human forced).
    //   +0  human loses (mate received).
    //   Plus fullmove-based time bonus for the human (rewards
    //   dragging the bot out): capped at 120.
    var score = 0;
    switch (state.status) {
      case ChessGameStatus.checkmate:
        final lastMover = _other(state.sideToMove);
        score = lastMover == humanColor ? 300 : 0;
        break;
      case ChessGameStatus.stalemate:
      case ChessGameStatus.drawByFiftyMove:
      case ChessGameStatus.drawByInsufficientMaterial:
      case ChessGameStatus.drawByRepetition:
        score = 150;
        break;
      case ChessGameStatus.ongoing:
        break;
    }
    final cappedMoveBonus =
        (state.fullmoveNumber * 4).clamp(0, 120);
    score += cappedMoveBonus;
    _onGameEnd?.call(score);
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }
}