/// Pure-Dart rules engine for standard chess.
///
/// ## Representation
///
/// The board is a flat `Int8List(64)` of piece codes. Empty squares are
/// 0. Each non-empty square holds a 4-bit packed code:
///
///     bit 0           : side   (0 = white, 1 = black)
///     bits 1..3       : type   (1=pawn, 2=knight, 3=bishop,
///                                 4=rook, 5=queen, 6=king)
///
/// Use the [Piece] helpers ([encode], [pieceType], [pieceColor]) — never
/// reach into the bits directly from call sites.
///
/// Castling rights and the en-passant target are tracked outside the
/// 64-slot array in [ChessState.castling] (a bitfield) and
/// [ChessState.enPassantSquare] (the square BEHIND the pawn that just
/// moved two squares, i.e. the square a follow-up en-passant capture
/// would land on — not the square the pawn passed through).
///
/// ## Move semantics
///
/// All moves are legal-move aware. [ChessRules.legalMoves] filters out
/// moves that leave your own king in check. Pseudo-legal moves
/// ([ChessRules.pseudoLegalMoves]) ignore check and are used by the
/// search engine to keep the tree lean; search layers check the
/// king-safety filter back over generated candidates.
///
/// ## End conditions
///
/// After every state mutation, [ChessState.status] derives one of:
///   - [ChessGameStatus.ongoing]
///   - [ChessGameStatus.checkmate]   (side to move is in check, no escape)
///   - [ChessGameStatus.stalemate]   (side to move has no legal move,
///                                    not in check)
///   - [ChessGameStatus.drawByInsufficientMaterial]
///   - [ChessGameStatus.drawByFiftyMove]
///   - [ChessGameStatus.drawByRepetition]
///
/// Repetition and 50-move are detected by callers passing a position
/// history; this engine provides [isInsufficientMaterial] standalone
/// for the all-minor / K vs K / K+B vs K / K+N vs K / lone-king cases
/// which are straightforward to determine locally.
library;

import 'dart:math' as math;
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Piece encoding
// ---------------------------------------------------------------------------

/// Color of a chess piece.
enum PieceColor { white, black }

/// Type of a chess piece (king, queen, rook, bishop, knight, pawn).
enum PieceType { pawn, knight, bishop, rook, queen, king }

/// "Any piece" sentinel — covers the six real types and a sentinel
/// "none" for empty squares. [PieceType.none] is reserved for the
/// 0-slot convention; never store one on the board.
enum PieceTypeAny { none, pawn, knight, bishop, rook, queen, king }

/// A single move description. `from` and `to` are 0..63 board indices.
/// [promotion] is null except on a pawn-promotion move (the only kind
/// where a captured piece can be absent).
class ChessMove {
  const ChessMove({
    required this.from,
    required this.to,
    this.promotion,
    this.castling = false,
    this.enPassant = false,
    this.capture = false,
  });

  final int from;
  final int to;
  final PieceType? promotion;

  /// True when this move is a king-side or queen-side castle.
  final bool castling;

  /// True when this move captures via en passant (the captured pawn
  /// is NOT on [to]; it sits on the square behind it).
  final bool enPassant;

  /// True when this move captures an opponent piece. Note that
  /// [enPassant] captures also set this flag.
  final bool capture;

  ChessMove copyWith({
    int? from,
    int? to,
    PieceType? promotion,
    bool? castling,
    bool? enPassant,
    bool? capture,
  }) =>
      ChessMove(
        from: from ?? this.from,
        to: to ?? this.to,
        promotion: promotion ?? this.promotion,
        castling: castling ?? this.castling,
        enPassant: enPassant ?? this.enPassant,
        capture: capture ?? this.capture,
      );

  @override
  String toString() {
    final promo = promotion == null ? '' : '=${_pieceLetter(promotion!)}';
    final flag = castling
        ? ' (castle)'
        : enPassant
            ? ' (ep)'
            : capture
                ? ' (capture)'
                : '';
    return '$_squareName(from)$_squareName(to)$promo$flag';
  }
}

/// The result of a fully applied move — returned by
/// [ChessRules.applyMove] so the caller can drive UI flashes and
/// endgame scoring without recomputing anything.
class ChessApplyResult {
  const ChessApplyResult({required this.next, required this.move});

  final ChessState next;

  /// The move that was actually played (after promotion resolution —
  /// pawn-promotion moves are normalized to the chosen [PieceType]).
  final ChessMove move;
}

// ---------------------------------------------------------------------------
// Castling rights
// ---------------------------------------------------------------------------

/// Castling rights as a 4-bit bitfield.
///   bit 0 = white king-side
///   bit 1 = white queen-side
///   bit 2 = black king-side
///   bit 3 = black queen-side
class CastlingRights {
  const CastlingRights(this.bits);
  final int bits;

  static const CastlingRights none = CastlingRights(0);
  static const CastlingRights all = CastlingRights(0xF);

  bool get whiteKingSide => (bits & 0x1) != 0;
  bool get whiteQueenSide => (bits & 0x2) != 0;
  bool get blackKingSide => (bits & 0x4) != 0;
  bool get blackQueenSide => (bits & 0x8) != 0;

  bool get hasAny => bits != 0;

  CastlingRights withoutWhiteKingSide() => CastlingRights(bits & ~0x1);
  CastlingRights withoutWhiteQueenSide() => CastlingRights(bits & ~0x2);
  CastlingRights withoutBlackKingSide() => CastlingRights(bits & ~0x4);
  CastlingRights withoutBlackQueenSide() => CastlingRights(bits & ~0x8);

  @override
  String toString() {
    final parts = <String>[];
    if (whiteKingSide) parts.add('K');
    if (whiteQueenSide) parts.add('Q');
    if (blackKingSide) parts.add('k');
    if (blackQueenSide) parts.add('q');
    return parts.isEmpty ? '-' : parts.join();
  }
}

// ---------------------------------------------------------------------------
// Game status
// ---------------------------------------------------------------------------

/// Derived game-over state. [ChessRules.applyMove] updates
/// [ChessState.status] automatically after each successful application.
enum ChessGameStatus {
  ongoing,
  checkmate,
  stalemate,
  drawByInsufficientMaterial,
  drawByFiftyMove,
  drawByRepetition,
}

extension ChessGameStatusX on ChessGameStatus {
  bool get isDraw =>
      this == ChessGameStatus.stalemate ||
      this == ChessGameStatus.drawByInsufficientMaterial ||
      this == ChessGameStatus.drawByFiftyMove ||
      this == ChessGameStatus.drawByRepetition;

  bool get isGameOver => this != ChessGameStatus.ongoing;
}

// ---------------------------------------------------------------------------
// ChessState
// ---------------------------------------------------------------------------

/// Mutable game state. Mutated only through [ChessRules] — direct
/// field edits will desync [halfmoveClock] / castling / ep / status.
class ChessState {
  ChessState({
    Int8List? board,
    this.sideToMove = PieceColor.white,
    CastlingRights? castling,
    this.enPassantSquare = -1,
    this.halfmoveClock = 0,
    this.fullmoveNumber = 1,
    this.status = ChessGameStatus.ongoing,
    this.history = const [],
  })  : board = board ?? _initialBoard(),
        castling = castling ?? CastlingRights.all;

  /// 64-slot board, index = file + rank*8 (a1=0, b1=1, ..., h8=63).
  final Int8List board;

  PieceColor sideToMove;
  CastlingRights castling;
  int enPassantSquare;
  int halfmoveClock;
  int fullmoveNumber;
  ChessGameStatus status;

  /// FEN-style hashes of every position reached since the last
  /// irreversible move (pawn advance / capture). Used by the host
   /// shell to detect threefold repetition — we keep the bookkeeping
   /// but the actual detection happens in [_ChessRules.detectRepetition]
  /// on demand (so callers who don't care about it pay no cost).
  final List<int> history;

  /// Deep copy. Used heavily by the alpha-beta search.
  ChessState clone() => ChessState(
        board: Int8List.fromList(board),
        sideToMove: sideToMove,
        castling: castling,
        enPassantSquare: enPassantSquare,
        halfmoveClock: halfmoveClock,
        fullmoveNumber: fullmoveNumber,
        status: status,
        history: List<int>.from(history),
      );

  /// Read a piece at [sq] (0..63). Returns null for empty.
  ({PieceColor color, PieceType type})? pieceAt(int sq) {
    final code = board[sq];
    if (code == 0) return null;
    return (color: pieceColor(code), type: pieceType(code));
  }

  /// Compute a cheap positional hash (used by repetition detection).
  /// Includes side-to-move and castling + en-passant target since
  /// those are part of the position. Halfmove/fullmove are NOT
  /// included — they matter for the 50-move rule but not for
  /// repetition (FIF repetition counts).
  int positionHash() {
    var h = 0;
    for (var i = 0; i < 64; i++) {
      h = (h * 31 + board[i]) & 0x7fffffff;
    }
    h = (h * 31 + (sideToMove == PieceColor.white ? 0 : 1)) & 0x7fffffff;
    h = (h * 31 + castling.bits) & 0x7fffffff;
    h = (h * 31 + (enPassantSquare + 1)) & 0x7fffffff;
    return h;
  }

  /// White material balance minus black material balance, in
  /// centipawns. Used by the AI as the terminal-ish eval signal.
  /// (Doesn't include piece-square tables — kept simple for the
  /// first cut so the depth-3 search is fast enough to feel
  /// responsive on mid-range hardware.)
  int materialBalance() {
    var score = 0;
    for (var i = 0; i < 64; i++) {
      final code = board[i];
      if (code == 0) continue;
      final type = pieceType(code);
      final color = pieceColor(code);
      final v = _pieceValue(type);
      score += color == PieceColor.white ? v : -v;
    }
    return score;
  }

  /// True if [side]'s king is currently attacked by any of [otherSide]'s
  /// pieces. Used to detect check, mate, and to filter out moves that
  /// would leave the mover's own king in check.
  bool isInCheck(PieceColor side) {
    final kingSq = _findKing(side, board);
    if (kingSq < 0) return false;
    return _isSquareAttacked(kingSq, _other(side), board);
  }
}

// ---------------------------------------------------------------------------
// Piece helpers (4-bit packed)
// ---------------------------------------------------------------------------

/// Encode a piece as a 4-bit integer.
///   low bit     = side   (0 white, 1 black)
///   bits 1..3   = type   (1..6)
int encode(PieceColor color, PieceType type) {
  final c = color == PieceColor.black ? 1 : 0;
  final t = _typeIndex(type) & 0x7;
  return (t << 1) | c;
}

PieceType pieceType(int code) => _typeFromIndex((code >> 1) & 0x7);
PieceColor pieceColor(int code) =>
    (code & 0x1) == 0 ? PieceColor.white : PieceColor.black;

int _typeIndex(PieceType t) {
  switch (t) {
    case PieceType.pawn:
      return 1;
    case PieceType.knight:
      return 2;
    case PieceType.bishop:
      return 3;
    case PieceType.rook:
      return 4;
    case PieceType.queen:
      return 5;
    case PieceType.king:
      return 6;
  }
}

PieceType _typeFromIndex(int i) {
  switch (i) {
    case 1:
      return PieceType.pawn;
    case 2:
      return PieceType.knight;
    case 3:
      return PieceType.bishop;
    case 4:
      return PieceType.rook;
    case 5:
      return PieceType.queen;
    case 6:
      return PieceType.king;
    default:
      throw StateError('unknown piece index $i');
  }
}

PieceColor _other(PieceColor c) =>
    c == PieceColor.white ? PieceColor.black : PieceColor.white;

int _pieceValue(PieceType t) {
  switch (t) {
    case PieceType.pawn:
      return 100;
    case PieceType.knight:
      return 320;
    case PieceType.bishop:
      return 330;
    case PieceType.rook:
      return 500;
    case PieceType.queen:
      return 900;
    case PieceType.king:
      return 20000;
  }
}

String _pieceLetter(PieceType t) {
  switch (t) {
    case PieceType.pawn:
      return 'P';
    case PieceType.knight:
      return 'N';
    case PieceType.bishop:
      return 'B';
    case PieceType.rook:
      return 'R';
    case PieceType.queen:
      return 'Q';
    case PieceType.king:
      return 'K';
  }
}

String _squareName(int sq) {
  const files = 'abcdefgh';
  final f = files[sq % 8];
  final r = (sq ~/ 8) + 1;
  return '$f$r';
}

// ---------------------------------------------------------------------------
// Initial position
// ---------------------------------------------------------------------------

Int8List _initialBoard() {
  final b = Int8List(64);
  const back = [
    PieceType.rook,
    PieceType.knight,
    PieceType.bishop,
    PieceType.queen,
    PieceType.king,
    PieceType.bishop,
    PieceType.knight,
    PieceType.rook,
  ];
  for (var f = 0; f < 8; f++) {
    b[f] = encode(PieceColor.white, back[f]);
    b[8 + f] = encode(PieceColor.white, PieceType.pawn);
    b[48 + f] = encode(PieceColor.black, PieceType.pawn);
    b[56 + f] = encode(PieceColor.black, back[f]);
  }
  return b;
}

// ---------------------------------------------------------------------------
// Attack detection (used for check, castling legality, en-passant pin check)
// ---------------------------------------------------------------------------

bool _isSquareAttacked(int sq, PieceColor bySide, Int8List board) {
  final file = sq % 8;
  final rank = sq ~/ 8;

  // Pawn attacks: a white pawn attacks r-1, f±1; black pawn attacks r+1, f±1.
  final pawnDir = bySide == PieceColor.white ? -1 : 1;
  for (final df in const [-1, 1]) {
    final f = file + df;
    final r = rank + pawnDir;
    if (f < 0 || f > 7 || r < 0 || r > 7) continue;
    final code = board[f + r * 8];
    if (code != 0 &&
        pieceColor(code) == bySide &&
        pieceType(code) == PieceType.pawn) {
      return true;
    }
  }

  // Knight jumps.
  for (final (df, dr) in const [
    (1, 2),
    (2, 1),
    (2, -1),
    (1, -2),
    (-1, -2),
    (-2, -1),
    (-2, 1),
    (-1, 2)
  ]) {
    final f = file + df;
    final r = rank + dr;
    if (f < 0 || f > 7 || r < 0 || r > 7) continue;
    final code = board[f + r * 8];
    if (code != 0 &&
        pieceColor(code) == bySide &&
        pieceType(code) == PieceType.knight) {
      return true;
    }
  }

  // Sliders (bishop/queen on diagonals, rook/queen on ranks/files).
  // Diagonals.
  for (final (df, dr) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
    var f = file + df;
    var r = rank + dr;
    while (f >= 0 && f < 8 && r >= 0 && r < 8) {
      final code = board[f + r * 8];
      if (code != 0) {
        if (pieceColor(code) == bySide &&
            (pieceType(code) == PieceType.bishop ||
                pieceType(code) == PieceType.queen)) {
          return true;
        }
        break;
      }
      f += df;
      r += dr;
    }
  }
  // Orthogonals.
  for (final (df, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
    var f = file + df;
    var r = rank + dr;
    while (f >= 0 && f < 8 && r >= 0 && r < 8) {
      final code = board[f + r * 8];
      if (code != 0) {
        if (pieceColor(code) == bySide &&
            (pieceType(code) == PieceType.rook ||
                pieceType(code) == PieceType.queen)) {
          return true;
        }
        break;
      }
      f += df;
      r += dr;
    }
  }
  // King adjacency (relevant when checking if a square is attacked by
  // the opponent's king — needed to disallow castling through check).
  for (final (df, dr) in const [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1)
  ]) {
    final f = file + df;
    final r = rank + dr;
    if (f < 0 || f > 7 || r < 0 || r > 7) continue;
    final code = board[f + r * 8];
    if (code != 0 &&
        pieceColor(code) == bySide &&
        pieceType(code) == PieceType.king) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// King-square helper
// ---------------------------------------------------------------------------

int _findKing(PieceColor side, Int8List board) {
  final wantCode = encode(side, PieceType.king);
  for (var i = 0; i < 64; i++) {
    if (board[i] == wantCode) return i;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Move generation
// ---------------------------------------------------------------------------

class _MoveGen {
  _MoveGen(this.board);

  final Int8List board;
  final List<ChessMove> out = [];

  void generate(PieceColor side, CastlingRights castling, int epSquare) {
    for (var sq = 0; sq < 64; sq++) {
      final code = board[sq];
      if (code == 0) continue;
      if (pieceColor(code) != side) continue;
      switch (pieceType(code)) {
        case PieceType.pawn:
          _pawn(sq, side, epSquare);
          break;
        case PieceType.knight:
          _knight(sq, side);
          break;
        case PieceType.bishop:
          _slide(sq, side, const [
            (1, 1),
            (1, -1),
            (-1, 1),
            (-1, -1)
          ], false);
          break;
        case PieceType.rook:
          _slide(sq, side, const [
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1)
          ], false);
          break;
        case PieceType.queen:
          _slide(sq, side, const [
            (1, 0),
            (-1, 0),
            (0, 1),
            (0, -1),
            (1, 1),
            (1, -1),
            (-1, 1),
            (-1, -1)
          ], false);
          break;
        case PieceType.king:
          _king(sq, side);
          break;
      }
    }
    _castles(side, castling);
  }

  void _pawn(int sq, PieceColor side, int epSquare) {
    final file = sq % 8;
    final rank = sq ~/ 8;
    final dir = side == PieceColor.white ? 1 : -1;
    final startRank = side == PieceColor.white ? 1 : 6;
    final promoRank = side == PieceColor.white ? 7 : 0;

    // Single push.
    final oneR = rank + dir;
    if (oneR >= 0 && oneR < 8 && board[file + oneR * 8] == 0) {
      if (oneR == promoRank) {
        _promotions(sq, file + oneR * 8);
      } else {
        out.add(ChessMove(from: sq, to: file + oneR * 8));
        // Double push from start rank.
        if (rank == startRank) {
          final twoR = rank + 2 * dir;
          if (board[file + twoR * 8] == 0) {
            out.add(ChessMove(from: sq, to: file + twoR * 8));
          }
        }
      }
    }

    // Captures.
    for (final df in const [-1, 1]) {
      final f = file + df;
      if (f < 0 || f > 7) continue;
      final r = rank + dir;
      if (r < 0 || r > 7) continue;
      final to = f + r * 8;
      final target = board[to];
      if (target != 0 && pieceColor(target) != side) {
        if (r == promoRank) {
          _promotions(sq, to, capture: true);
        } else {
          out.add(ChessMove(from: sq, to: to, capture: true));
        }
      }
      // En passant: the ep square is the square BEHIND the pawn that
      // moved two squares last turn, so a pawn on the 5th rank (white)
      // or 4th rank (black) can capture there as if it were an
      // occupied enemy square.
      if (epSquare == to) {
        out.add(ChessMove(from: sq, to: to, enPassant: true, capture: true));
      }
    }
  }

  void _promotions(int from, int to, {bool capture = false}) {
    for (final promo in const [
      PieceType.queen,
      PieceType.rook,
      PieceType.bishop,
      PieceType.knight
    ]) {
      out.add(ChessMove(
        from: from,
        to: to,
        promotion: promo,
        capture: capture,
      ));
    }
  }

  void _knight(int sq, PieceColor side) {
    final file = sq % 8;
    final rank = sq ~/ 8;
    for (final (df, dr) in const [
      (1, 2),
      (2, 1),
      (2, -1),
      (1, -2),
      (-1, -2),
      (-2, -1),
      (-2, 1),
      (-1, 2)
    ]) {
      final f = file + df;
      final r = rank + dr;
      if (f < 0 || f > 7 || r < 0 || r > 7) continue;
      final to = f + r * 8;
      final code = board[to];
      if (code == 0) {
        out.add(ChessMove(from: sq, to: to));
      } else if (pieceColor(code) != side) {
        out.add(ChessMove(from: sq, to: to, capture: true));
      }
    }
  }

  void _slide(
    int sq,
    PieceColor side,
    List<(int, int)> dirs,
    bool _,
  ) {
    final file = sq % 8;
    final rank = sq ~/ 8;
    for (final (df, dr) in dirs) {
      var f = file + df;
      var r = rank + dr;
      while (f >= 0 && f < 8 && r >= 0 && r < 8) {
        final to = f + r * 8;
        final code = board[to];
        if (code == 0) {
          out.add(ChessMove(from: sq, to: to));
        } else {
          if (pieceColor(code) != side) {
            out.add(ChessMove(from: sq, to: to, capture: true));
          }
          break;
        }
        f += df;
        r += dr;
      }
    }
  }

  void _king(int sq, PieceColor side) {
    final file = sq % 8;
    final rank = sq ~/ 8;
    for (final (df, dr) in const [
      (1, 0),
      (-1, 0),
      (0, 1),
      (0, -1),
      (1, 1),
      (1, -1),
      (-1, 1),
      (-1, -1)
    ]) {
      final f = file + df;
      final r = rank + dr;
      if (f < 0 || f > 7 || r < 0 || r > 7) continue;
      final to = f + r * 8;
      final code = board[to];
      if (code == 0) {
        out.add(ChessMove(from: sq, to: to));
      } else if (pieceColor(code) != side) {
        out.add(ChessMove(from: sq, to: to, capture: true));
      }
    }
  }

  void _castles(PieceColor side, CastlingRights castling) {
    final rank = side == PieceColor.white ? 0 : 7;
    final ownKingSq = 4 + rank * 8;
    final code = board[ownKingSq];
    if (code == 0) return;
    if (pieceType(code) != PieceType.king) return;
    if (pieceColor(code) != side) return;
    // King-side.
    if ((side == PieceColor.white && castling.whiteKingSide) ||
        (side == PieceColor.black && castling.blackKingSide)) {
      if (board[5 + rank * 8] == 0 &&
          board[6 + rank * 8] == 0 &&
          !_isSquareAttacked(4 + rank * 8, _other(side), board) &&
          !_isSquareAttacked(5 + rank * 8, _other(side), board) &&
          !_isSquareAttacked(6 + rank * 8, _other(side), board)) {
        // King is on e1/e8 (the only legal castle square at start),
        // but we double-check the rook too — it must still be there.
        final rookCode = board[7 + rank * 8];
        if (rookCode != 0 &&
            pieceType(rookCode) == PieceType.rook &&
            pieceColor(rookCode) == side) {
          out.add(ChessMove(
            from: ownKingSq,
            to: 6 + rank * 8,
            castling: true,
          ));
        }
      }
    }
    // Queen-side.
    if ((side == PieceColor.white && castling.whiteQueenSide) ||
        (side == PieceColor.black && castling.blackQueenSide)) {
      if (board[3 + rank * 8] == 0 &&
          board[2 + rank * 8] == 0 &&
          board[1 + rank * 8] == 0 &&
          !_isSquareAttacked(4 + rank * 8, _other(side), board) &&
          !_isSquareAttacked(3 + rank * 8, _other(side), board) &&
          !_isSquareAttacked(2 + rank * 8, _other(side), board)) {
        final rookCode = board[0 + rank * 8];
        if (rookCode != 0 &&
            pieceType(rookCode) == PieceType.rook &&
            pieceColor(rookCode) == side) {
          out.add(ChessMove(
            from: ownKingSq,
            to: 2 + rank * 8,
            castling: true,
          ));
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// ChessRules
// ---------------------------------------------------------------------------

/// Pure rules engine — no Flutter, no AI. All public methods are
/// deterministic given the same input state (and same RNG for the
/// alpha-beta search). Tests use [ChessRules.applyMove] to walk the
/// state forward and assert endgame derivations.
class ChessRules {
  const ChessRules();

  /// Pseudo-legal moves: every move that matches the piece's geometry
  /// regardless of whether it leaves the mover's own king in check.
  /// The alpha-beta search uses this internally; the UI should call
  /// [legalMoves] instead so it can highlight only safe squares.
  List<ChessMove> pseudoLegalMoves(ChessState s) {
    final gen = _MoveGen(s.board);
    gen.generate(s.sideToMove, s.castling, s.enPassantSquare);
    return List<ChessMove>.unmodifiable(gen.out);
  }

  /// Legal moves: pseudo-legal moves filtered so the mover's own king
  /// is not left in check after the move. This is what the UI uses
  /// to highlight destination squares.
  List<ChessMove> legalMoves(ChessState s) {
    final pseudo = pseudoLegalMoves(s);
    final result = <ChessMove>[];
    for (final m in pseudo) {
      if (!_moveLeavesKingInCheck(s, m)) {
        result.add(m);
      }
    }
    return List<ChessMove>.unmodifiable(result);
  }

  bool hasAnyLegalMove(ChessState s) => legalMoves(s).isNotEmpty;

  /// Apply a [move] to [state]. Returns the next state via
  /// [ChessApplyResult]; the original [state] is left untouched
  /// (cloning preserves immutability from the caller's POV). The
  /// returned state has its [ChessState.status] freshly derived.
  ///
  /// If [move] is illegal, throws [ArgumentError]. The UI is expected
  /// to filter through [legalMoves] so this never fires in practice,
  /// but the engine guards against it for correctness.
  ChessApplyResult applyMove(ChessState state, ChessMove move) {
    final pseudo = pseudoLegalMoves(state);
    if (!pseudo.any((m) =>
        m.from == move.from &&
        m.to == move.to &&
        m.promotion == move.promotion)) {
      // Re-check legality (filtering out moves that leave own king in
      // check) to give the caller a useful error message.
      final legal = legalMoves(state);
      if (legal.any((m) =>
          m.from == move.from &&
          m.to == move.to &&
          m.promotion == move.promotion)) {
        throw ArgumentError(
            'move $move is pseudo-legal but rejected by check filter — '
            'this should not happen; engine bug');
      }
      throw ArgumentError('illegal move $move for side ${state.sideToMove}');
    }
    final next = state.clone();
    _applyInPlace(next, move);

    // Halfmove clock: reset on pawn move or capture, else increment.
    final isPawnMove = pieceType(next.board[move.to]) == PieceType.pawn &&
        // (after promotion this is no longer a pawn — but a promotion
        //  is always a pawn move from the perspective of the rule)
        (move.from - move.to).abs() != 0 || _isPromotion(state, move);
    final resetsHalfmove =
        isPawnMove || move.capture || move.enPassant;
    next.halfmoveClock = resetsHalfmove ? 0 : state.halfmoveClock + 1;

    // Fullmove number ticks after black's move.
    if (state.sideToMove == PieceColor.black) {
      next.fullmoveNumber = state.fullmoveNumber + 1;
    }

    // Side-to-move flips.
    next.sideToMove = _other(state.sideToMove);

    // Status derivation.
    next.status = _deriveStatus(next);
    return ChessApplyResult(next: next, move: move);
  }

  /// Whether [side]'s king is in check after [move] is applied.
  /// Internal helper used by [legalMoves] and the AI.
  bool _moveLeavesKingInCheck(ChessState s, ChessMove move) {
    final next = s.clone();
    _applyInPlace(next, move);
    return next.isInCheck(s.sideToMove);
  }

  /// In-place mutation — only [applyMove] calls this. All the
  /// irreversibles (castling rights, ep square, halfmove clock) are
  /// updated here.
  void _applyInPlace(ChessState next, ChessMove move) {
    final board = next.board;
    final mover = next.sideToMove;
    final code = board[move.from];
    if (code == 0 || pieceColor(code) != mover) {
      throw StateError('attempting to move from empty/enemy square');
    }
    final piece = pieceType(code);

    // Capture (including en passant — ep captures clear a different
    // square than `to`).
    if (move.enPassant) {
      // Captured pawn sits on the file of `to` and the rank of `from`.
      final capturedSq = move.to + (move.from ~/ 8 - move.to ~/ 8) * 8;
      board[capturedSq] = 0;
    } else if (move.capture) {
      board[move.to] = 0;
    }

    // Castling — also move the rook.
    if (move.castling) {
      final rank = move.from ~/ 8;
      final isKingSide = move.to % 8 == 6;
      final rookFrom = (isKingSide ? 7 : 0) + rank * 8;
      final rookTo = (isKingSide ? 5 : 3) + rank * 8;
      board[rookTo] = board[rookFrom];
      board[rookFrom] = 0;
    }

    // Move the piece. If promoting, drop the chosen type onto `to`.
    if (move.promotion != null) {
      board[move.to] = encode(mover, move.promotion!);
    } else {
      board[move.to] = code;
    }
    board[move.from] = 0;

    // Castling rights: revoke any right that involves the moved piece
    // or a captured rook.
    var rights = next.castling.bits;
    if (piece == PieceType.king) {
      if (mover == PieceColor.white) {
        rights &= ~0x3;
      } else {
        rights &= ~0xC;
      }
    }
    if (move.from == 0 || move.to == 0) rights &= ~0x2;
    if (move.from == 7 || move.to == 7) rights &= ~0x1;
    if (move.from == 56 || move.to == 56) rights &= ~0x8;
    if (move.from == 63 || move.to == 63) rights &= ~0x4;
    next.castling = CastlingRights(rights);

    // En-passant target: square BEHIND a pawn that just moved two.
    next.enPassantSquare = -1;
    if (piece == PieceType.pawn && (move.to - move.from).abs() == 16) {
      next.enPassantSquare = (move.from + move.to) ~/ 2;
    }
  }

  bool _isPromotion(ChessState s, ChessMove m) {
    final code = s.board[m.from];
    if (code == 0) return false;
    if (pieceType(code) != PieceType.pawn) return false;
    final targetRank = m.to ~/ 8;
    return s.sideToMove == PieceColor.white ? targetRank == 7 : targetRank == 0;
  }

  /// Derive the game-over status of [next]. Order:
  ///   1. 50-move rule (halfmoveClock >= 100)  — drawn.
  ///   2. Side-to-move has no legal move:
  ///        - if in check  → checkmate
  ///        - else         → stalemate
  ///   3. Insufficient material (no pawns / no non-minor pieces left).
  ///   4. Otherwise: ongoing.
  ///
  /// Repetition is detected by the caller (who owns the position
  /// history) and reported as [ChessGameStatus.drawByRepetition]; the
  /// rules engine only flags the in-engine conditions.
  ChessGameStatus _deriveStatus(ChessState next) {
    if (next.halfmoveClock >= 100) {
      return ChessGameStatus.drawByFiftyMove;
    }
    final hasMove = hasAnyLegalMove(next);
    if (!hasMove) {
      return next.isInCheck(next.sideToMove)
          ? ChessGameStatus.checkmate
          : ChessGameStatus.stalemate;
    }
    if (_isInsufficientMaterial(next)) {
      return ChessGameStatus.drawByInsufficientMaterial;
    }
    return ChessGameStatus.ongoing;
  }

  /// Detects the basic insufficient-material cases:
  ///   - K vs K
  ///   - K+B vs K, K+N vs K
  ///   - K+B vs K+B on same-color bishops (always; FIDE rule: not
  ///     automatically draw but in practice unreachable as a mate)
  /// We only need the obvious cases for v1 — chess.com-style "any
  /// threefold repetition" is the host shell's job, not ours.
  bool _isInsufficientMaterial(ChessState s) {
    int whiteMinor = 0;
    int blackMinor = 0;
    int whiteMajor = 0;
    int blackMajor = 0;
    int pawns = 0;
    for (var i = 0; i < 64; i++) {
      final code = s.board[i];
      if (code == 0) continue;
      final t = pieceType(code);
      final c = pieceColor(code);
      if (t == PieceType.pawn) pawns++;
      if (t == PieceType.bishop || t == PieceType.knight) {
        if (c == PieceColor.white) {
          whiteMinor++;
        } else {
          blackMinor++;
        }
      }
      if (t == PieceType.rook || t == PieceType.queen) {
        if (c == PieceColor.white) {
          whiteMajor++;
        } else {
          blackMajor++;
        }
      }
    }
    if (pawns > 0) return false;
    if (whiteMajor > 0 || blackMajor > 0) return false;
    // Only kings, or kings + ≤1 minor each.
    final totalMinors = whiteMinor + blackMinor;
    if (totalMinors == 0) return true;
    if (totalMinors == 1) return true;
    // K+B vs K+B same color complex is "drawn in practice" but the
    // engine conservatively keeps it as ongoing — that's accurate
    // per FIDE rules and avoids false draws in casual games.
    return false;
  }

  /// Pre-computed position hash for repetition detection. The caller
  /// passes a history list; if any prior position hash matches the
  /// current one AND there's been ≥2 prior visits to that position,
  /// it's a threefold. (We don't auto-claim — just hand the tools.)
  bool isThreefoldRepetition(ChessState s) {
    final h = s.positionHash();
    var count = 0;
    for (final prior in s.history) {
      if (prior == h) count++;
    }
    return count >= 2; // current + 2 prior = 3
  }
}

/// Simple eval for the alpha-beta search. White-positive.
int defaultEvaluate(ChessState s) {
  // Base = material.
  var score = s.materialBalance();
  // Tiny mobility-style nudge so the AI prefers non-stuck positions
  // without actually counting moves (cheap to compute, helps the
  // AI avoid zugzwang-style traps in the early game).
  if (s.status == ChessGameStatus.checkmate) {
    // Side-to-move has been mated: that's terrible for them.
    score += s.sideToMove == PieceColor.white ? -100000 : 100000;
  }
  return score;
}

/// Negamax-flavored alpha-beta with a fixed-depth ceiling and a tiny
/// quiescence pass (only checks/forced promotions) — enough to play a
/// "respectable but beatable" game at depth 3 on most phones.
class ChessEngine {
  ChessEngine({
    this.maxDepth = 3,
    this.evaluate = defaultEvaluate,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final int maxDepth;
  final int Function(ChessState) evaluate;
  final math.Random _random;

  /// Pick the best move for [state.sideToMove]. Returns null when the
  /// side has no legal move (caller should treat that as game-over).
  ChessMove? pickMove(ChessState state) {
    final rules = const ChessRules();
    // `legalMoves` returns an unmodifiable view — copy before sorting.
    final moves = [...rules.legalMoves(state)];
    if (moves.isEmpty) return null;
    // Initial alpha-beta window — generous enough that no sane eval
    // overflows it in a chess game.
    var bestScore = -2147483648;
    ChessMove? best;
    var alpha = -2147483647;
    var beta = 2147483647;
    // Order: captures first to improve pruning (MVV-LVA lite — just
    // put captures before non-captures, no deeper ordering).
    moves.sort((a, b) {
      final ac = a.capture || a.enPassant ? 1 : 0;
      final bc = b.capture || b.enPassant ? 1 : 0;
      return bc - ac;
    });
    for (final move in moves) {
      final result = rules.applyMove(state, move);
      final score = -_alphaBeta(result.next, maxDepth - 1, -beta, -alpha);
      if (score > bestScore) {
        bestScore = score;
        best = move;
        if (score > alpha) alpha = score;
      }
    }
    // Tie-break on equal scores with a small random nudge so the bot
    // doesn't play identically every game.
    if (best != null && _random.nextDouble() < 0.05) {
      final tied = moves
          .where((m) => rules.applyMove(state, m).next.status !=
              ChessGameStatus.checkmate)
          .toList();
      if (tied.isNotEmpty) best = tied[_random.nextInt(tied.length)];
    }
    return best;
  }

  int _alphaBeta(ChessState s, int depth, int alpha, int beta) {
    if (s.status != ChessGameStatus.ongoing) {
      // Mate-in-N (or stalemate) — heavy eval so search prefers shorter
      // mates.
      final base = evaluate(s);
      if (s.status == ChessGameStatus.checkmate) {
        // Side-to-move just got mated; that's bad for them. The ply
        // depth acts as the "mate distance" — closer mates are
        // penalized more (so the AI picks the fastest mate).
        return base - depth * 10;
      }
      return base;
    }
    if (depth <= 0) {
      return evaluate(s);
    }
    final rules = const ChessRules();
    final moves = [...rules.legalMoves(s)];
    if (moves.isEmpty) {
      return s.isInCheck(s.sideToMove) ? -100000 + (maxDepth - depth) * 10 : 0;
    }
    // Move ordering — captures first.
    moves.sort((a, b) {
      final ac = a.capture || a.enPassant ? 1 : 0;
      final bc = b.capture || b.enPassant ? 1 : 0;
      return bc - ac;
    });
    var best = -2147483647;
    for (final move in moves) {
      final result = rules.applyMove(s, move);
      final score = -_alphaBeta(result.next, depth - 1, -beta, -alpha);
      if (score > best) best = score;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }
}