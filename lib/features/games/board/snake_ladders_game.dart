import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Snake & Ladders — ported from
/// `downloaded_games/games/SnakeLadders/game.py`.
///
/// 10×10 board (cells 1..100), 2-player pass-and-play. Each turn:
///   1. Tap "Roll" — animated dice settles to a random value 1..6.
///   2. Piece walks that many cells one-at-a-time with a smooth
///      step animation.
///   3. If the new cell is the bottom of a ladder → climb to the top.
///      If it's the head of a snake → slide down to the tail.
///   4. Switch turn. First player to reach cell 100 wins.
///
/// Ladder + snake positions are hard-coded from the python source.
class SnakeLaddersGame extends MiniGame {
  const SnakeLaddersGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// Optional level — controls board size variation; defaults to 1.
  final int level;

  @override
  State<SnakeLaddersGame> createState() => _SnakeLaddersGameState();
}

enum _SLState { roll, animatingDice, movingSteps, gameOver }

class _SnakeLaddersGameState extends MiniGameState<SnakeLaddersGame> {
  static const Map<int, int> _ladders = <int, int>{
    3: 22, 8: 30, 28: 65, 52: 75, 58: 77, 62: 81, 69: 91,
  };
  static const Map<int, int> _snakes = <int, int>{
    17: 4, 43: 18, 54: 31, 67: 46, 89: 48, 93: 71, 98: 79,
  };

  int _p1Pos = 1;
  int _p2Pos = 1;
  int _currentPlayer = 1;
  int _lastRoll = 1;
  _SLState _state = _SLState.roll;
  String _message = 'Roll to start!';

  // Dice animation
  int _diceAnimFrames = 0;
  int _diceAnimVal = 1;

  // Piece animation
  bool _pieceAnimating = false;
  Timer? _pieceTimer;
  int _pieceToCell = 1;
  int _pieceStepIndex = 0;
  int _pieceStepsTotal = 0;
  bool _pieceIsSnakeOrLadder = false;
  int _pieceFinalCell = 1;

  static const Color _bg = Color(0xFF0A0A14);
  static const Color _boardBg = Color(0xFF0E1020);
  static const Color _gridBorder = Color(0xFF19203A);
  static const Color _cellEven = Color(0xFF14182D);
  static const Color _cellOdd = Color(0xFF191E38);
  static const Color _border = Color(0xFF00EBFF);
  static const Color _ladder = Color(0xFF00FFA0);
  static const Color _ladderRail = Color(0xFF009664);
  static const Color _snake = Color(0xFFFF0064);
  static const Color _snakeHead = Color(0xFFFF5096);
  static const Color _p1 = Color(0xFF00EBFF);
  static const Color _p2 = Color(0xFFFFD700);
  static const Color _panel = Color(0xFF101220);
  static const Color _text = Color(0xFFE1E6FF);
  static const Color _textDim = Color(0xFF646E96);
  static const Color _diceBg = Color(0xFF16182C);

  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(0);
      _updateStats();
    });
  }

  @override
  void dispose() {
    _pieceTimer?.cancel();
    super.dispose();
  }

  // ─── Game logic ───────────────────────────────────────────────────────

  void _onRollTap() {
    if (_state != _SLState.roll) return;
    setState(() {
      _state = _SLState.animatingDice;
      _diceAnimFrames = 12;
    });
    _tickDice();
  }

  void _tickDice() {
    if (_diceAnimFrames <= 0) {
      _startPieceMove();
      return;
    }
    Future.delayed(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      setState(() {
        _diceAnimVal = _rng.nextInt(6) + 1;
        _diceAnimFrames--;
      });
      _tickDice();
    });
  }

  void _startPieceMove() {
    final roll = _rng.nextInt(6) + 1;
    _lastRoll = roll;
    final startPos = _currentPlayer == 1 ? _p1Pos : _p2Pos;
    var nextPos = startPos + roll;
    if (nextPos > 100) nextPos = startPos; // need exact roll to win
    final steps = nextPos - startPos;

    _pieceToCell = nextPos;
    _pieceStepsTotal = steps;
    _pieceStepIndex = 0;
    _pieceIsSnakeOrLadder = false;
    _pieceFinalCell = nextPos;
    _pieceAnimating = true;
    _state = _SLState.movingSteps;

    _stepPiece();
  }

  void _stepPiece() {
    if (_pieceStepIndex >= _pieceStepsTotal) {
      _onStepDone();
      return;
    }
    _pieceToCell++;
    _pieceStepIndex++;
    setState(() {});
    _pieceTimer?.cancel();
    _pieceTimer = Timer(const Duration(milliseconds: 240), _stepPiece);
  }

  void _onStepDone() {
    // Check snake / ladder at final cell.
    final cell = _pieceToCell;
    int? jumpTo;
    String jumpKind;
    if (_ladders.containsKey(cell)) {
      jumpTo = _ladders[cell];
      jumpKind = 'Ladder';
    } else if (_snakes.containsKey(cell)) {
      jumpTo = _snakes[cell];
      jumpKind = 'Snake';
    } else {
      jumpTo = null;
      jumpKind = '';
    }
    if (jumpTo != null) {
      final dest = jumpTo;
      _pieceIsSnakeOrLadder = true;
      _pieceFinalCell = dest;
      _pieceToCell = dest;
      _message = '$jumpKind! → $dest';
      haptic(jumpKind == 'Ladder'
          ? HapticFeedbackType.medium
          : HapticFeedbackType.heavy);
      setState(() {});
      _pieceTimer?.cancel();
      _pieceTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        _finishMove(dest);
      });
    } else {
      _finishMove(cell);
    }
  }

  void _finishMove(int finalCell) {
    setState(() {
      if (_currentPlayer == 1) {
        _p1Pos = finalCell;
      } else {
        _p2Pos = finalCell;
      }
      _pieceAnimating = false;
    });
    if (finalCell == 100) {
      _message =
          _currentPlayer == 1 ? 'Player 1 wins!' : 'Player 2 wins!';
      setState(() {
        _state = _SLState.gameOver;
      });
      haptic(HapticFeedbackType.heavy);
      reportScore(500);
      _updateStats();
      reportGameOver();
      return;
    }
    // Switch turn.
    setState(() {
      _currentPlayer = _currentPlayer == 1 ? 2 : 1;
      _state = _SLState.roll;
      _message = 'Player $_currentPlayer — roll!';
    });
    _updateStats();
  }

  void _reset() {
    _pieceTimer?.cancel();
    setState(() {
      _p1Pos = 1;
      _p2Pos = 1;
      _currentPlayer = 1;
      _lastRoll = 1;
      _state = _SLState.roll;
      _message = 'Roll to start!';
      _pieceAnimating = false;
    });
    reportScore(0);
    _updateStats();
  }

  void _updateStats() {
    final turn = _state == _SLState.gameOver
        ? 'Game over'
        : 'P$_currentPlayer turn · roll $_lastRoll';
    reportStats(
      'P1 $_p1Pos · P2 $_p2Pos · $turn',
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxBoard = c.maxWidth < c.maxHeight
                ? c.maxWidth - 200
                : c.maxHeight - 80;
            final cell = (maxBoard / 10).clamp(20.0, 56.0);
            final boardSize = cell * 10;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: _buildBoard(cell),
                    ),
                  ),
                ),
                _buildSidePanel(boardSize),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBoard(double cell) {
    return Container(
      decoration: BoxDecoration(
        color: _boardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border.withValues(alpha: 0.4), width: 2),
      ),
      child: Stack(
        children: [
          CustomPaint(
            size: Size(cell * 10, cell * 10),
            painter: _SLBoardPainter(
              cell: cell,
              p1: _p1,
              p2: _p2,
              ladder: _ladder,
              ladderRail: _ladderRail,
              snake: _snake,
              snakeHead: _snakeHead,
              gridBorder: _gridBorder,
              cellEven: _cellEven,
              cellOdd: _cellOdd,
              text: _text,
              textDim: _textDim,
              p1Pos: _p1Pos,
              p2Pos: _p2Pos,
              pieceAnimating: _pieceAnimating,
              pieceCurrentCell: _pieceToCell,
              pieceIsJump: _pieceIsSnakeOrLadder,
              pieceFinalCell: _pieceFinalCell,
              currentPlayer: _currentPlayer,
            ),
          ),
          // Tap target for dice button is the side panel — no overlay needed.
        ],
      ),
    );
  }

  Widget _buildSidePanel(double boardSize) {
    return Container(
      width: 170,
      color: _panel,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SNAKES & LADDERS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _border,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _playerChip('Player 1', _p1Pos, _p1,
              isActive: _currentPlayer == 1 && _state != _SLState.gameOver),
          const SizedBox(height: 6),
          _playerChip('Player 2', _p2Pos, _p2,
              isActive: _currentPlayer == 2 && _state != _SLState.gameOver),
          const Spacer(),
          _diceWidget(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _onRollTap,
              icon: const Icon(Icons.casino_rounded),
              label: Text(_state == _SLState.gameOver ? 'New game' : 'Roll'),
              style: FilledButton.styleFrom(
                backgroundColor: _border,
                foregroundColor: const Color(0xFF002030),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _message.contains('wins')
                  ? _p2
                  : (_message.contains('Snake')
                      ? _snake
                      : (_message.contains('Ladder') ? _ladder : _text)),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, color: _textDim),
            label: const Text(
              'Restart',
              style: TextStyle(color: _textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerChip(String name, int pos, Color color,
      {required bool isActive}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isActive ? 0.9 : 0.4),
        ),
      ),
      child: Row(
        children: [
          Text(
            name,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            '$pos',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diceWidget() {
    final value = _state == _SLState.animatingDice ? _diceAnimVal : _lastRoll;
    final spinning = _state == _SLState.animatingDice;
    return Center(
      child: AnimatedRotation(
        turns: spinning ? _diceAnimVal / 6 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: _diceBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border, width: 2),
            boxShadow: [
              BoxShadow(
                color: _border.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(
              color: _border,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _SLBoardPainter extends CustomPainter {
  _SLBoardPainter({
    required this.cell,
    required this.p1,
    required this.p2,
    required this.ladder,
    required this.ladderRail,
    required this.snake,
    required this.snakeHead,
    required this.gridBorder,
    required this.cellEven,
    required this.cellOdd,
    required this.text,
    required this.textDim,
    required this.p1Pos,
    required this.p2Pos,
    required this.pieceAnimating,
    required this.pieceCurrentCell,
    required this.pieceIsJump,
    required this.pieceFinalCell,
    required this.currentPlayer,
  });

  final double cell;
  final Color p1;
  final Color p2;
  final Color ladder;
  final Color ladderRail;
  final Color snake;
  final Color snakeHead;
  final Color gridBorder;
  final Color cellEven;
  final Color cellOdd;
  final Color text;
  final Color textDim;
  final int p1Pos;
  final int p2Pos;
  final bool pieceAnimating;
  final int pieceCurrentCell;
  final bool pieceIsJump;
  final int pieceFinalCell;
  final int currentPlayer;

  static const Map<int, int> _ladders = <int, int>{
    3: 22, 8: 30, 28: 65, 52: 75, 58: 77, 62: 81, 69: 91,
  };
  static const Map<int, int> _snakes = <int, int>{
    17: 4, 43: 18, 54: 31, 67: 46, 89: 48, 93: 71, 98: 79,
  };

  Offset _cellTopLeft(int cellNum) {
    final idx = cellNum - 1;
    final row = idx ~/ 10;
    var col = idx % 10;
    if (row.isOdd) col = 9 - col;
    return Offset(col * cell, (9 - row) * cell);
  }

  Offset _cellCenter(int cellNum) =>
      _cellTopLeft(cellNum) + Offset(cell / 2, cell / 2);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw cells.
    for (var i = 1; i <= 100; i++) {
      final tl = _cellTopLeft(i);
      final rect = Rect.fromLTWH(tl.dx, tl.dy, cell, cell);
      final isEven = (i % 2 == 0);
      canvas.drawRect(rect, Paint()..color = isEven ? cellEven : cellOdd);
      canvas.drawRect(
        rect,
        Paint()
          ..color = gridBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      // Cell number.
      if (i % 10 == 0 || i == 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(
              color: textDim,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, tl + Offset(3, 2));
      }
    }

    // Draw ladders.
    for (final entry in _ladders.entries) {
      final a = _cellCenter(entry.key);
      final b = _cellCenter(entry.value);
      _drawLadder(canvas, a, b);
    }

    // Draw snakes.
    for (final entry in _snakes.entries) {
      final a = _cellCenter(entry.key);
      final b = _cellCenter(entry.value);
      _drawSnake(canvas, a, b);
    }

    // Draw pieces.
    _drawPiece(canvas, p1Pos, p1, 'P1');
    _drawPiece(canvas, p2Pos, p2, 'P2');
  }

  void _drawLadder(Canvas canvas, Offset from, Offset to) {
    final railPaint = Paint()
      ..color = ladderRail
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dx = (to.dx - from.dx) / 10;
    final dy = (to.dy - from.dy) / 10;
    canvas.drawLine(
      Offset(from.dx - 6, from.dy),
      Offset(to.dx - 6, to.dy),
      railPaint,
    );
    canvas.drawLine(
      Offset(from.dx + 6, from.dy),
      Offset(to.dx + 6, to.dy),
      railPaint,
    );
    final rungsPaint = Paint()
      ..color = ladder
      ..strokeWidth = 2;
    for (var i = 1; i < 10; i += 2) {
      final p1 = Offset(from.dx - 6 + dx * i, from.dy + dy * i);
      final p2 = Offset(from.dx + 6 + dx * i, from.dy + dy * i);
      canvas.drawLine(p1, p2, rungsPaint);
    }
  }

  void _drawSnake(Canvas canvas, Offset from, Offset to) {
    final body = Path()..moveTo(from.dx, from.dy);
    final steps = 12;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final x = from.dx + (to.dx - from.dx) * t;
      final y = from.dy + (to.dy - from.dy) * t;
      final wave = sin(t * pi * 4) * 8;
      body.lineTo(x + wave, y);
    }
    final paint = Paint()
      ..color = snake
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(body, paint);
    // Head
    canvas.drawCircle(
      Offset(from.dx, from.dy),
      5,
      Paint()..color = snakeHead,
    );
  }

  void _drawPiece(Canvas canvas, int pos, Color color, String tag) {
    // If animating and this is the moving piece, draw at the
    // animated cell instead of the resting cell.
    if (pieceAnimating &&
        ((tag == 'P1' && currentPlayer == 1) ||
            (tag == 'P2' && currentPlayer == 2))) {
      pos = pieceIsJump ? pieceFinalCell : pieceCurrentCell;
    }
    final center = _cellCenter(pos);
    final r = cell * 0.18;
    // Shadow.
    canvas.drawCircle(
      center + const Offset(1, 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Body.
    canvas.drawCircle(center, r, Paint()..color = color);
    // Highlight.
    canvas.drawCircle(
      center + Offset(-r * 0.3, -r * 0.3),
      r * 0.3,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
    // Tag.
    final tp = TextPainter(
      text: TextSpan(
        text: tag,
        style: TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_SLBoardPainter old) =>
      old.p1Pos != p1Pos ||
      old.p2Pos != p2Pos ||
      old.pieceAnimating != pieceAnimating ||
      old.pieceCurrentCell != pieceCurrentCell ||
      old.pieceFinalCell != pieceFinalCell ||
      old.currentPlayer != currentPlayer ||
      old.cell != cell;
}
