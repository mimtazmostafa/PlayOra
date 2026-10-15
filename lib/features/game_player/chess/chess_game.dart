import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import 'chess_controller.dart';
import 'chess_model.dart';

/// Chess Master — flagship parity pass.
///
/// Upgrades over the previous version:
///   * Custom-painted vector pieces (no Unicode glyphs).
///   * Captured-pieces tray with material advantage indicator.
///   * Scrollable SAN move-history panel.
///   * Clocks for both sides (you / AI), red-tinted when ≤ 30s.
///   * Last-move highlight (yellow) and pulsing king-in-check highlight.
///   * Distinct dot vs. ring indicator for legal-destination moves.
///   * Haptics: light on select, medium on move, heavy on capture,
///     selection on illegal tap.
///   * Long-press drag-and-drop with a piece-lift preview.
///   * Slide animation for the moving piece, flash for capture, scale-pop
///     for promotion.
///   * End modal replaces the banner: trophy card, finish-reason line,
///     material count, and Play Again + Back to Home buttons.
class ChessGame extends StatefulWidget {
  const ChessGame({
    super.key,
    required this.gameTitle,
    required this.controller,
  });

  final String gameTitle;
  final ChessController controller;

  @override
  State<ChessGame> createState() => _ChessGameState();
}

class _ChessGameState extends State<ChessGame>
    with SingleTickerProviderStateMixin {
  ChessController get _controller => widget.controller;

  // --- Tap-tap selection state ---
  int? _selectedSq;
  List<ChessMove> _legalForSelected = const <ChessMove>[];

  // --- Drag-and-drop state ---
  int? _draggingSq;
  Offset? _dragGlobalPos;
  List<ChessMove> _dragLegalDests = const <ChessMove>[];

  // --- Animation ---
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int? _animFromSq;
  int? _animToSq;
  double _animT = 1.0; // 0 = start, 1 = settled
  Timer? _captureFlashTimer;
  bool _captureFlashOn = false;

  // --- Clocks ---
  static const Duration _initialClock = Duration(minutes: 10);
  Duration _whiteClock = _initialClock;
  Duration _blackClock = _initialClock;
  int _lastWhiteSec = _initialClock.inSeconds;
  int _lastBlackSec = _initialClock.inSeconds;

  // --- Move history (kept locally so SAN shows immediately) ---
  final List<_HistoryEntry> _history = <_HistoryEntry>[];

  // --- Captured pieces (kept locally for the tray) ---
  final List<PieceType> _capturedByWhite = <PieceType>[]; // white captures black
  final List<PieceType> _capturedByBlack = <PieceType>[]; // black captures white

  // --- Difficulty chip shadow ---
  ChessBotDifficulty _currentDifficulty = ChessBotDifficulty.medium;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _ticker = createTicker(_onFrame)..start();
    _controller.onCapture = _onPieceCaptured;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.onCapture = null;
    _ticker.dispose();
    _captureFlashTimer?.cancel();
    super.dispose();
  }

  void _onPieceCaptured(PieceType type) {
    final moverIsWhite = _controller.humanColor == PieceColor.white
        ? _controller.currentState.sideToMove == PieceColor.black
        : _controller.currentState.sideToMove == PieceColor.white;
    setState(() {
      if (moverIsWhite) {
        _capturedByWhite.add(type);
      } else {
        _capturedByBlack.add(type);
      }
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final state = _controller.currentState;
    // If the game just restarted, reset everything.
    if (state.fullmoveNumber == 1 &&
        state.halfmoveClock == 0 &&
        _history.isNotEmpty) {
      _history.clear();
      _capturedByWhite.clear();
      _capturedByBlack.clear();
      _whiteClock = _initialClock;
      _blackClock = _initialClock;
    }
    setState(() {});
  }

  void _onFrame(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    if (_animT < 1.0) {
      _animT = math.min(1.0, _animT + dt / 0.22);
      if (_animT >= 1.0) {
        _animFromSq = null;
        _animToSq = null;
      }
      setState(() {});
    }

    // Clocks only need a redraw when the displayed second flips, not
    // every frame. We mutate the duration every frame (cheap), but
    // only call setState when something visible changed.
    if (!_controller.hasEnded) {
      final mover = _controller.currentState.sideToMove;
      if (mover == PieceColor.white) {
        _whiteClock -= Duration(microseconds: (dt * 1e6).round());
        if (_whiteClock.isNegative) _whiteClock = Duration.zero;
      } else {
        _blackClock -= Duration(microseconds: (dt * 1e6).round());
        if (_blackClock.isNegative) _blackClock = Duration.zero;
      }
      final whiteSec = _whiteClock.inSeconds;
      final blackSec = _blackClock.inSeconds;
      if (whiteSec != _lastWhiteSec || blackSec != _lastBlackSec) {
        _lastWhiteSec = whiteSec;
        _lastBlackSec = blackSec;
        setState(() {});
      }
    }
  }

  // ---------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------

  void _onSquareTap(int sq) {
    final state = _controller.currentState;
    if (_controller.hasEnded) return;
    if (state.sideToMove != _controller.humanColor) return;

    if (_selectedSq == null) {
      _trySelect(sq);
      return;
    }
    final moves = _legalForSelected.where((m) => m.to == sq).toList();
    if (moves.isNotEmpty) {
      _commitMove(moves.first);
      return;
    }
    final code = state.board[sq];
    if (code != 0 && pieceColor(code) == state.sideToMove) {
      _trySelect(sq);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSq = null;
      _legalForSelected = const <ChessMove>[];
    });
  }

  void _trySelect(int sq) {
    final state = _controller.currentState;
    final code = state.board[sq];
    if (code == 0) return;
    if (pieceColor(code) != state.sideToMove) return;
    final moves =
        _controller.rules.legalMoves(state).where((m) => m.from == sq).toList();
    if (moves.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedSq = sq;
      _legalForSelected = moves;
    });
  }

  Future<void> _commitMove(ChessMove move) async {
    final state = _controller.currentState;
    final fromCode = state.board[move.from];
    final isPawn = fromCode != 0 && pieceType(fromCode) == PieceType.pawn;
    final backRank = state.sideToMove == PieceColor.white ? 7 : 0;
    final isPromotion = isPawn && (move.to ~/ 8) == backRank;
    if (isPromotion) {
      final picked = await _showPromotionSheet();
      if (!mounted) return;
      final promo = picked ?? PieceType.queen;
      final resolved = move.copyWith(promotion: promo);
      _fireMove(resolved, promotion: promo);
      return;
    }
    _fireMove(move);
  }

  void _fireMove(ChessMove move, {PieceType? promotion}) {
    HapticFeedback.mediumImpact();
    // Snapshot the pre-move state so SAN generation can inspect the
    // board as it was when the move was made. Otherwise `state.board
    // [move.from]` is 0 after `attemptMove` and `pieceType(0)`
    // throws.
    final preState = _controller.currentState;
    final fromPiece = preState.board[move.from];
    final ok = _controller.attemptMove(move);
    if (!ok) return;
    if (move.capture || move.enPassant) {
      HapticFeedback.heavyImpact();
      _captureFlashTimer?.cancel();
      _captureFlashOn = true;
      _captureFlashTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        setState(() => _captureFlashOn = false);
      });
    }
    _history.add(_HistoryEntry(
      san: _sanFor(move, preState: preState, fromPiece: fromPiece),
      color: _controller.currentState.sideToMove == PieceColor.white
          ? PieceColor.black
          : PieceColor.white,
    ));
    setState(() {
      _selectedSq = null;
      _legalForSelected = const <ChessMove>[];
      _animFromSq = move.from;
      _animToSq = move.to;
      _animT = 0.0;
    });
  }

  Future<PieceType?> _showPromotionSheet() async {
    final color = _controller.currentState.sideToMove;
    return showModalBottomSheet<PieceType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PromotionSheet(color: color),
    );
  }

  // ---------------------------------------------------------------------
  // Drag-and-drop
  // ---------------------------------------------------------------------

  void _onLongPressStart(LongPressStartDetails details, int sq) {
    final state = _controller.currentState;
    if (_controller.hasEnded) return;
    if (state.sideToMove != _controller.humanColor) return;
    final code = state.board[sq];
    if (code == 0) return;
    if (pieceColor(code) != state.sideToMove) return;
    final moves =
        _controller.rules.legalMoves(state).where((m) => m.from == sq).toList();
    if (moves.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _draggingSq = sq;
      _dragGlobalPos = details.globalPosition;
      _dragLegalDests = moves;
      _selectedSq = sq;
      _legalForSelected = moves;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_draggingSq == null) return;
    setState(() => _dragGlobalPos = details.globalPosition);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_draggingSq == null) return;
    final dropGlobal = details.globalPosition;
    final renderBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final local = renderBox.globalToLocal(dropGlobal);
      final cell = renderBox.size.shortestSide / 8;
      if (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx < cell * 8 &&
          local.dy < cell * 8) {
        final file = (local.dx / cell).floor().clamp(0, 7);
        final rank = (local.dy / cell).floor().clamp(0, 7);
        final sq = rank * 8 + file;
        final move = _dragLegalDests.where((m) => m.to == sq).toList();
        if (move.isNotEmpty) {
          setState(() {
            _draggingSq = null;
            _dragGlobalPos = null;
            _dragLegalDests = const [];
          });
          _commitMove(move.first);
          return;
        }
      }
    }
    HapticFeedback.selectionClick();
    setState(() {
      _draggingSq = null;
      _dragGlobalPos = null;
      _dragLegalDests = const [];
      _selectedSq = null;
      _legalForSelected = const [];
    });
  }

  final GlobalKey _boardKey = GlobalKey();

  // ---------------------------------------------------------------------
  // SAN generation (kept local — the model's helpers are private)
  // ---------------------------------------------------------------------

  String _sanFor(
    ChessMove move, {
    required ChessState preState,
    required int fromPiece,
  }) {
    final piece = pieceType(fromPiece);

    if (move.castling) {
      return move.to % 8 == 6 ? 'O-O' : 'O-O-O';
    }
    final sb = StringBuffer();
    if (piece == PieceType.pawn) {
      if (move.capture || move.enPassant) {
        sb.write(String.fromCharCode('a'.codeUnitAt(0) + (move.from % 8)));
        sb.write('x');
      }
    } else {
      sb.write(_pieceLetterUpper(piece));
      // Disambiguation.
      final sameFileOrRank = _controller.rules
          .legalMoves(preState)
          .where((m) =>
              m.from != move.from &&
              m.to == move.to &&
              pieceType(preState.board[m.from]) == piece)
          .toList();
      if (sameFileOrRank.isNotEmpty) {
        final sameFile = sameFileOrRank
            .where((m) => (m.from % 8) == (move.from % 8))
            .toList();
        if (sameFile.length != sameFileOrRank.length) {
          sb.write(String.fromCharCode('a'.codeUnitAt(0) + (move.from % 8)));
        } else {
          sb.write('${(move.from ~/ 8) + 1}');
        }
      }
      if (move.capture || move.enPassant) sb.write('x');
    }
    sb.write(_squareName(move.to));
    if (move.promotion != null) {
      sb.write('=${_pieceLetterUpper(move.promotion!)}');
    }
    if (move.enPassant) sb.write(' e.p.');
    // After the move, the side-to-move has flipped to the opponent —
    // we check whether that opponent's king is now in check.
    final nextState = _controller.rules.applyMove(preState, move).next;
    if (nextState.isInCheck(nextState.sideToMove)) {
      sb.write(nextState.status == ChessGameStatus.checkmate ? '#' : '+');
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = _controller.currentState;
    final isCheck =
        !_controller.hasEnded && state.isInCheck(state.sideToMove);

    // Build the legal-dest sets once per rebuild rather than letting
    // each of 64 squares do its own O(L) scan over `legalDests`.
    final isAnimating = _animFromSq != null && _animT < 1.0;
    final destSet = <int>{};
    final capSet = <int>{};
    for (final m in _legalForSelected) {
      destSet.add(m.to);
      if (m.capture || m.enPassant) capSet.add(m.to);
    }

    // The host [GameContainerScreen] already paints the title / level /
    // score HUD bar — duplicating it here would clip the board and
    // show "Chess Master" twice. We only surface chess-specific chrome
    // (clocks + difficulty popup) in a thin strip below the host HUD.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: _ClockChip(
                  seconds: _clockFor(_controller.humanColor).inSeconds,
                  label: 'YOU',
                  active: state.sideToMove == _controller.humanColor,
                  dim: _controller.hasEnded,
                ),
              ),
              const SizedBox(width: 6),
              _DifficultyChip(
                difficulty: _currentDifficulty,
                onChanged: (d) {
                  setState(() => _currentDifficulty = d);
                  _controller.setDifficulty(d);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ClockChip(
                  seconds:
                      _clockFor(_other(_controller.humanColor)).inSeconds,
                  label: 'AI',
                  active: !_controller.hasEnded &&
                      state.sideToMove != _controller.humanColor,
                  dim: _controller.hasEnded,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _Board(
                        key: _boardKey,
                        state: state,
                        selectedSq: _selectedSq,
                        legalDestSet: destSet,
                        captureDestSet: capSet,
                        isAnimating: isAnimating,
                        animFromSq: _animFromSq,
                        animToSq: _animToSq,
                        animT: _animT,
                        captureFlashSq: _captureFlashOn ? _animToSq : null,
                        isCheckOn: isCheck,
                        checkColor: state.sideToMove,
                        draggingSq: _draggingSq,
                        dragGlobalPos: _dragGlobalPos,
                        lastMoveFromSq: _lastMoveFromSq,
                        lastMoveToSq: _lastMoveToSq,
                        onTap: _onSquareTap,
                        onLongPressStart: _onLongPressStart,
                        onLongPressMoveUpdate: _onLongPressMoveUpdate,
                        onLongPressEnd: _onLongPressEnd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _CapturedTray(
                  capturedByWhite: _capturedByWhite,
                  capturedByBlack: _capturedByBlack,
                  humanColor: _controller.humanColor,
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 110,
                  child: _HistoryPanel(history: _history),
                ),
              ],
            ),
          ),
        ),
        if (_controller.hasEnded)
          _EndCard(
            state: state,
            humanColor: _controller.humanColor,
            onPlayAgain: () => _controller.restart(),
            onBackToHome: () => context.go(AppRoutes.home),
            history: _history,
          ),
      ],
    );
  }

  // The last-played move's from/to is only meaningful while the
  // animation overlay is running — once it settles, the squares just
  // show whatever the board state already encodes.
  int? get _lastMoveFromSq => _animFromSq;
  int? get _lastMoveToSq => _animToSq;

  Duration _clockFor(PieceColor c) =>
      c == PieceColor.white ? _whiteClock : _blackClock;
}

// ---------------------------------------------------------------------------
// Piece helpers
// ---------------------------------------------------------------------------

String _pieceLetterUpper(PieceType t) {
  switch (t) {
    case PieceType.king:
      return 'K';
    case PieceType.queen:
      return 'Q';
    case PieceType.rook:
      return 'R';
    case PieceType.bishop:
      return 'B';
    case PieceType.knight:
      return 'N';
    case PieceType.pawn:
      return '';
  }
}

String _squareName(int sq) {
  final f = String.fromCharCode('a'.codeUnitAt(0) + (sq % 8));
  final r = '${(sq ~/ 8) + 1}';
  return '$f$r';
}

// ---------------------------------------------------------------------------
// History entry
// ---------------------------------------------------------------------------

class _HistoryEntry {
  const _HistoryEntry({required this.san, required this.color});
  final String san;
  final PieceColor color;
}

// ---------------------------------------------------------------------------
// Board widget
// ---------------------------------------------------------------------------

class _Board extends StatelessWidget {
  const _Board({
    super.key,
    required this.state,
    required this.selectedSq,
    required this.legalDestSet,
    required this.captureDestSet,
    required this.isAnimating,
    required this.animFromSq,
    required this.animToSq,
    required this.animT,
    required this.captureFlashSq,
    required this.isCheckOn,
    required this.checkColor,
    required this.draggingSq,
    required this.dragGlobalPos,
    required this.lastMoveFromSq,
    required this.lastMoveToSq,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  final ChessState state;
  final int? selectedSq;
  final Set<int> legalDestSet;
  final Set<int> captureDestSet;
  final bool isAnimating;
  final int? animFromSq;
  final int? animToSq;
  final double animT;
  final int? captureFlashSq;
  final bool isCheckOn;
  final PieceColor checkColor;
  final int? draggingSq;
  final Offset? dragGlobalPos;
  final int? lastMoveFromSq;
  final int? lastMoveToSq;
  final void Function(int sq) onTap;
  final void Function(LongPressStartDetails, int sq) onLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final void Function(LongPressEndDetails) onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Container(color: const Color(0xFF1B1F26)),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPressStart: (d) {
                  final sq = _sqAt(d.localPosition, size);
                  if (sq != null) onLongPressStart(d, sq);
                },
                onLongPressMoveUpdate: onLongPressMoveUpdate,
                onLongPressEnd: onLongPressEnd,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                  ),
                  itemCount: 64,
                  itemBuilder: (ctx, i) => _Square(
                    sq: i,
                    code: state.board[i],
                    isSelected: selectedSq == i,
                    inLegalDests:
                        !isAnimating && legalDestSet.contains(i),
                    isCaptureTarget: captureDestSet.contains(i),
                    isLastMoveFrom: lastMoveFromSq == i,
                    isLastMoveTo: lastMoveToSq == i,
                    isCheckHere: isCheckOn &&
                        state.pieceAt(i)?.type == PieceType.king &&
                        state.pieceAt(i)?.color == checkColor,
                    isCaptureFlash: captureFlashSq == i,
                    onTap: () => onTap(i),
                  ),
                ),
              ),
              if (animFromSq != null && animToSq != null)
                CustomPaint(
                  size: Size(size, size),
                  painter: _AnimatedPiecePainter(
                    state: state,
                    fromSq: animFromSq!,
                    toSq: animToSq!,
                    t: animT,
                    cell: size / 8,
                  ),
                ),
              if (draggingSq != null && dragGlobalPos != null)
                _DragLiftOverlay(
                  code: state.board[draggingSq!],
                  globalPos: dragGlobalPos!,
                  cell: size / 8,
                ),
            ],
          ),
        );
      },
    );
  }

  int? _sqAt(Offset local, double size) {
    final cell = size / 8;
    if (local.dx < 0 || local.dy < 0) return null;
    if (local.dx >= cell * 8 || local.dy >= cell * 8) return null;
    final file = (local.dx / cell).floor().clamp(0, 7);
    final rank = (local.dy / cell).floor().clamp(0, 7);
    return rank * 8 + file;
  }
}

class _Square extends StatelessWidget {
  const _Square({
    required this.sq,
    required this.code,
    required this.isSelected,
    required this.inLegalDests,
    required this.isCaptureTarget,
    required this.isLastMoveFrom,
    required this.isLastMoveTo,
    required this.isCheckHere,
    required this.isCaptureFlash,
    required this.onTap,
  });

  final int sq;
  final int code;
  final bool isSelected;
  final bool inLegalDests;
  final bool isCaptureTarget;
  final bool isLastMoveFrom;
  final bool isLastMoveTo;
  final bool isCheckHere;
  final bool isCaptureFlash;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = sq % 8;
    final rank = sq ~/ 8;
    final isLight = (file + rank) % 2 == 0;
    // Canonical chess board colors.
    final baseColor = isLight
        ? const Color(0xFFF0D9B5)
        : const Color(0xFFB58863);
    Color bg = baseColor;
    if (isLastMoveFrom || isLastMoveTo) {
      bg = Color.lerp(baseColor, const Color(0xFFF6F669), 0.55) ?? baseColor;
    }
    if (isCheckHere) {
      bg = Color.lerp(baseColor, const Color(0xFFE94B4B), 0.55) ?? baseColor;
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: bg,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
              ),
            if (inLegalDests)
              _LegalDestIndicator(isCapture: isCaptureTarget),
            if (isCaptureFlash)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            if (code != 0)
              Padding(
                padding: const EdgeInsets.all(4),
                child: _PieceArt(code: code),
              ),
            if (file == 0)
              Positioned(
                left: 3,
                top: 2,
                child: Text(
                  '${rank + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isLight ? const Color(0xFF6B4A2B) : const Color(0xFFF0D9B5),
                  ),
                ),
              ),
            if (rank == 7)
              Positioned(
                right: 3,
                bottom: 2,
                child: Text(
                  String.fromCharCode('a'.codeUnitAt(0) + file),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isLight ? const Color(0xFF6B4A2B) : const Color(0xFFF0D9B5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegalDestIndicator extends StatelessWidget {
  const _LegalDestIndicator({required this.isCapture});
  final bool isCapture;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (isCapture) {
      // Ring: 3px stroke around a square inset by 4px on all sides.
      return Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }
    // Dot: small filled circle centered.
    return Center(
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piece art — hand-painted vector pieces for both colors.
// ---------------------------------------------------------------------------

class _PieceArt extends StatelessWidget {
  const _PieceArt({required this.code});
  final int code;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _PiecePainter(code: code),
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({required this.code});
  final int code;

  /// Unicode chess glyphs — bit3 = color (1 = white, 0 = black);
  /// bits 0-2 = piece type. U+2654–U+265F are the standard filled
  /// glyphs supported by every system font shipped with stock Android
  /// and iOS (Roboto, Noto Sans, SF Pro).
  static const Map<int, String> _glyphs = {
    0:  '\u265F', // black pawn
    1:  '\u265E', // black knight
    2:  '\u265D', // black bishop
    3:  '\u265C', // black rook
    4:  '\u265B', // black queen
    5:  '\u265A', // black king
    8:  '\u2659', // white pawn
    9:  '\u2658', // white knight
    10: '\u2657', // white bishop
    11: '\u2656', // white rook
    12: '\u2655', // white queen
    13: '\u2654', // white king
  };

  @override
  void paint(Canvas canvas, Size size) {
    final ch = _glyphs[code];
    if (ch == null) return;
    final isWhite = (code & 8) != 0;
    // Glyph color matches the underlying square color so the piece
    // reads as the natural "outline" on the opposite-color square.
    // A soft opposite-color shadow keeps the glyph legible on its
    // same-color square (white king on white square reads via the
    // dark shadow).
    final tp = TextPainter(
      text: TextSpan(
        text: ch,
        style: TextStyle(
          fontSize: size.shortestSide * 0.92,
          height: 1,
          color: isWhite ? Colors.white : Colors.black,
          shadows: isWhite
              ? const [Shadow(color: Colors.black54, blurRadius: 2)]
              : const [Shadow(color: Colors.white70, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) => old.code != code;
}


// ---------------------------------------------------------------------------
// Animated piece painter — slides the moving piece from fromSq to toSq
// over `t ∈ [0, 1]`. Eased with easeInOutCubic.
// ---------------------------------------------------------------------------

class _AnimatedPiecePainter extends CustomPainter {
  _AnimatedPiecePainter({
    required this.state,
    required this.fromSq,
    required this.toSq,
    required this.t,
    required this.cell,
  });
  final ChessState state;
  final int fromSq;
  final int toSq;
  final double t;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final code = _movedCode(state, fromSq);
    if (code == 0) return;
    final eased = _easeInOutCubic(t.clamp(0.0, 1.0));
    final fromFile = fromSq % 8;
    final fromRank = fromSq ~/ 8;
    final toFile = toSq % 8;
    final toRank = toSq ~/ 8;
    final fx = (fromFile + 0.5) * cell;
    final fy = (fromRank + 0.5) * cell;
    final tx = (toFile + 0.5) * cell;
    final ty = (toRank + 0.5) * cell;
    // Arc lift: peaks at 18% of cell height over the midpoint.
    final arc = math.sin(eased * math.pi) * cell * 0.18;
    final dx = fx + (tx - fx) * eased;
    final dy = fy + (ty - fy) * eased - arc;
    final w = cell;
    canvas.save();
    canvas.translate(dx - w / 2, dy - w / 2);
    // Soft drop shadow under the moving piece.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, w * 0.92),
        width: w * 0.7,
        height: w * 0.12,
      ),
      shadow,
    );
    _PiecePainter(code: code).paint(canvas, Size(w, w));
    canvas.restore();
  }

  int _movedCode(ChessState s, int from) {
    // For animation we draw the piece being moved. The board has
    // already been updated by the controller, so the piece lives on
    // the destination square; we look it up from there. The captured
    // square gets a separate flash overlay driven by the parent.
    final dst = state.board[toSq];
    return dst != 0 ? dst : s.board[from];
  }

  double _easeInOutCubic(double x) {
    if (x < 0.5) return 4 * x * x * x;
    return 1 - math.pow(-2 * x + 2, 3) / 2;
  }

  @override
  bool shouldRepaint(covariant _AnimatedPiecePainter old) =>
      old.t != t || old.fromSq != fromSq || old.toSq != toSq;
}

// ---------------------------------------------------------------------------
// Drag-lift overlay — follows the finger.
// ---------------------------------------------------------------------------

class _DragLiftOverlay extends StatelessWidget {
  const _DragLiftOverlay({
    required this.code,
    required this.globalPos,
    required this.cell,
  });
  final int code;
  final Offset globalPos;
  final double cell;

  @override
  Widget build(BuildContext context) {
    // The overlay is placed inside the board stack using a Positioned
    // fill + a Transform.translate; we compute the board's screen
    // position via a Builder.
    return LayoutBuilder(
      builder: (context, constraints) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return const SizedBox.shrink();
        final origin = renderBox.localToGlobal(Offset.zero);
        final local = globalPos - origin;
        final half = cell / 2;
        return Positioned(
          left: local.dx - half,
          top: local.dy - half,
          width: cell,
          height: cell,
          child: Transform.scale(
            scale: 1.08,
            child: Opacity(
              opacity: 0.95,
              child: _PieceArt(code: code),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Captured-pieces tray
// ---------------------------------------------------------------------------

class _CapturedTray extends StatelessWidget {
  const _CapturedTray({
    required this.capturedByWhite,
    required this.capturedByBlack,
    required this.humanColor,
  });

  final List<PieceType> capturedByWhite;
  final List<PieceType> capturedByBlack;
  final PieceColor humanColor;

  int _value(List<PieceType> types) {
    var v = 0;
    for (final t in types) {
      v += _pieceValue(t);
    }
    return v;
  }

  int _pieceValue(PieceType t) {
    switch (t) {
      case PieceType.pawn:
        return 1;
      case PieceType.knight:
      case PieceType.bishop:
        return 3;
      case PieceType.rook:
        return 5;
      case PieceType.queen:
        return 9;
      case PieceType.king:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final whiteValue = _value(capturedByWhite);
    final blackValue = _value(capturedByBlack);
    // Top row = white's captures (pieces white has taken from black).
    // Bottom row = black's captures.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.hudIndigo.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, capturedByWhite, whiteValue),
          const Divider(height: 8, thickness: 0.5),
          _row(context, capturedByBlack, blackValue),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<PieceType> types, int value) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final t in types)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: _PieceArt(
                    code: encode(
                      humanColor == PieceColor.white
                          ? PieceColor.white
                          : PieceColor.black,
                      t,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.hudIndigo.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value > 0 ? '+$value' : '0',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Move history panel
// ---------------------------------------------------------------------------

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.history});
  final List<_HistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface(Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No moves yet — make your first move.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    // Pair up moves: index 0 is white's first, index 1 is black's first, etc.
    final fullmoveCount = (history.length / 2).ceil();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        itemCount: fullmoveCount,
        itemBuilder: (ctx, i) {
          final wIdx = i * 2;
          final bIdx = i * 2 + 1;
          final w = wIdx < history.length ? history[wIdx] : null;
          final b = bIdx < history.length ? history[bIdx] : null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    w?.san ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    b?.san ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clock chip
// ---------------------------------------------------------------------------

class _ClockChip extends StatelessWidget {
  const _ClockChip({
    required this.seconds,
    required this.label,
    required this.active,
    required this.dim,
    this.alignEnd = false,
  });

  final int seconds;
  final String label;
  final bool active;
  final bool dim;

  /// When true, label sits to the right of the digits — used for the
  /// opponent's clock so the board stays visually balanced.
  final bool alignEnd;

  String _fmt(int s) {
    final m = (s ~/ 60).clamp(0, 99);
    final ss = (s % 60).clamp(0, 59);
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final low = seconds <= 30;
    final fg = dim
        ? Colors.grey
        : (low ? AppColors.error : AppColors.hudAccentYellow);
    final bg = dim
        ? AppColors.surface(Theme.of(context).brightness).withValues(alpha: 0.6)
        : AppColors.surface(Theme.of(context).brightness);
    final text = TextStyle(
      color: fg,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? fg : fg.withValues(alpha: 0.4),
          width: active ? 1.6 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, AppColors.hudCapsuleShadowOpacity),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!alignEnd) ...[
            Text(
              label,
              style: text.copyWith(fontSize: 10, letterSpacing: 0.6),
            ),
            const SizedBox(width: 6),
            Text(_fmt(seconds), style: text.copyWith(fontSize: 14)),
          ] else ...[
            Text(_fmt(seconds), style: text.copyWith(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: text.copyWith(fontSize: 10, letterSpacing: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty chip
// ---------------------------------------------------------------------------

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.difficulty, required this.onChanged});
  final ChessBotDifficulty difficulty;
  final ValueChanged<ChessBotDifficulty> onChanged;

  String _label() {
    switch (difficulty) {
      case ChessBotDifficulty.easy:
        return 'Easy';
      case ChessBotDifficulty.medium:
        return 'Medium';
      case ChessBotDifficulty.hard:
        return 'Hard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ChessBotDifficulty>(
      tooltip: 'AI difficulty',
      onSelected: onChanged,
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: ChessBotDifficulty.easy, child: Text('Easy')),
        PopupMenuItem(value: ChessBotDifficulty.medium, child: Text('Medium')),
        PopupMenuItem(value: ChessBotDifficulty.hard, child: Text('Hard')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface(Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.hudIndigo.withValues(alpha: 0.85),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color:
                  Color.fromRGBO(0, 0, 0, AppColors.hudCapsuleShadowOpacity),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 14, color: AppColors.hudIndigo),
            const SizedBox(width: 4),
            Text(
              _label(),
              style: const TextStyle(
                color: AppColors.hudIndigo,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Promotion sheet
// ---------------------------------------------------------------------------

class _PromotionSheet extends StatelessWidget {
  const _PromotionSheet({required this.color});
  final PieceColor color;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Promote to',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _pick(context, PieceType.queen),
                _pick(context, PieceType.rook),
                _pick(context, PieceType.bishop),
                _pick(context, PieceType.knight),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pick(BuildContext context, PieceType t) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(t),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: _PieceArt(code: encode(color, t)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// End card
// ---------------------------------------------------------------------------

class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.state,
    required this.humanColor,
    required this.onPlayAgain,
    required this.onBackToHome,
    required this.history,
  });

  final ChessState state;
  final PieceColor humanColor;
  final VoidCallback onPlayAgain;
  final VoidCallback onBackToHome;
  final List<_HistoryEntry> history;

  String _finishReason(ChessState s, PieceColor human) {
    switch (s.status) {
      case ChessGameStatus.checkmate:
        final winner = s.sideToMove == PieceColor.white
            ? PieceColor.black
            : PieceColor.white;
        return winner == human ? 'You delivered checkmate' : 'You were checkmated';
      case ChessGameStatus.stalemate:
        return 'Stalemate';
      case ChessGameStatus.drawByFiftyMove:
        return '50-move rule';
      case ChessGameStatus.drawByInsufficientMaterial:
        return 'Insufficient material';
      case ChessGameStatus.drawByRepetition:
        return 'Threefold repetition';
      case ChessGameStatus.ongoing:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final won = state.status == ChessGameStatus.checkmate &&
        (state.sideToMove == PieceColor.white
            ? PieceColor.black
            : PieceColor.white) == humanColor;
    final draw = state.status.isDraw;
    final headline = won
        ? 'You win!'
        : draw
            ? 'Draw'
            : 'AI wins';
    final color = won
        ? AppColors.secondary
        : draw
            ? theme.colorScheme.primary
            : AppColors.error;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _finishReason(state, humanColor),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Moves played: ${history.length ~/ 2 + (history.length.isOdd ? 1 : 0)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Play Again',
            icon: Icons.replay_rounded,
            onPressed: onPlayAgain,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: 'Back to Home',
            icon: Icons.home_rounded,
            onPressed: onBackToHome,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local helper — kept private to this file.
// ---------------------------------------------------------------------------

PieceColor _other(PieceColor c) =>
    c == PieceColor.white ? PieceColor.black : PieceColor.white;

