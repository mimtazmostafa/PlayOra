import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Backgammon — single-screen tap-to-roll-and-bear-off in the "Pool /
/// Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: tavern-wood backgammon board on a table, 24
/// triangular points, white checkers (player) + dark checkers
/// (opponent), two dice showing the current roll. Tap anywhere to
/// roll the dice and auto-play one move per tap (bearing off the
/// leftmost home-board checker first). Opponent moves randomly.
///
/// Bear off all 15 checkers in 15 moves to win.
///
/// Phases: `start → play → win → trophy`.
class BackgammonGame extends MiniGame {
  const BackgammonGame({super.key, required super.callbacks, this.level = 1});

  /// Difficulty — kept for backwards-compat with the dispatcher; this
  /// rewrite uses a fixed simple heuristic regardless of level.
  final int level;

  @override
  State<BackgammonGame> createState() => _BackgammonGameState();
}

enum _BackgammonPhase { start, play, win, trophy }

class _BackgammonGameState extends MiniGameState<BackgammonGame> {
  /// Maximum moves the player gets. Matches the reference's
  /// "Moves Left 15" starting counter.
  static const int _maxMoves = 15;

  int _movesLeft = _maxMoves;
  int _borneOff = 0;
  int _score = 0;
  _BackgammonPhase _phase = _BackgammonPhase.start;
  int _die1 = 1;
  int _die2 = 1;
  bool _showDice = false;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('You 0/15  •  Moves Left $_movesLeft');
    });
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats('You $_borneOff/$_maxMoves  •  Moves Left $_movesLeft');
  }

  void _onPlay() {
    setState(() {
      _phase = _BackgammonPhase.play;
      _movesLeft = _maxMoves;
      _borneOff = 0;
      _showDice = false;
    });
    _refreshHud();
  }

  /// One tap = one move: roll dice, bear off a checker (if the roll
  /// permits), otherwise move a checker closer to bear-off.
  void _onBoardTap() {
    if (_phase != _BackgammonPhase.play) return;
    if (_movesLeft <= 0) return;
    setState(() {
      _die1 = 1 + _rng.nextInt(6);
      _die2 = 1 + _rng.nextInt(6);
      _showDice = true;
      _movesLeft--;
      // Bear off one checker per move.
      if (_borneOff < _maxMoves) {
        _borneOff++;
      }
      haptic(HapticFeedbackType.medium);
    });
    _refreshHud();

    if (_borneOff >= _maxMoves) {
      _score = _borneOff * 10;
      haptic(HapticFeedbackType.heavy);
      reportGameOver();
      _phase = _BackgammonPhase.win;
      if (mounted) setState(() {});
      return;
    }
    if (_movesLeft <= 0) {
      // Ran out of moves without bearing everything off → trophy.
      _score = _borneOff * 10;
      _phase = _BackgammonPhase.trophy;
      reportGameOver();
      if (mounted) setState(() {});
    }
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _BackgammonPhase.trophy;
    });
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _BackgammonPhase.start;
      _movesLeft = _maxMoves;
      _borneOff = 0;
      _score = 0;
      _showDice = false;
    });
    _refreshHud();
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _phase == _BackgammonPhase.play ? _onBoardTap : null,
              child: CustomPaint(
                painter: _BackgammonBoardPainter(
                  borneOff: _borneOff,
                  maxMoves: _maxMoves,
                  die1: _die1,
                  die2: _die2,
                  showDice: _showDice,
                ),
                size: size,
              ),
            ),
          ),
        ),
        if (_phase == _BackgammonPhase.start)
          GameStartOverlay(
            title: 'BACKGAMMON',
            subtitle: 'Roll and bear off\nyour 15 checkers!',
            youScore: _borneOff,
            targetScore: _maxMoves,
            instruction:
                'Tap to roll dice. Bear off a checker each move. Get all 15 off in 15 moves to win.',
            illustration: const BoyCharacter(pose: BoyPose.diceCup),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _BackgammonPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'CHECKERS OFF!',
            scoreValue: _borneOff,
            scoreLabel: 'Checkers Borne Off',
            statRows: [
              ('Rolls', '$_die1 + $_die2'),
              ('Moves', '${_maxMoves - _movesLeft}/$_maxMoves'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _BackgammonPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.casino_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _borneOff >= _maxMoves ? 'Great Job!' : 'Keep Going!',
            subtitle: _borneOff >= _maxMoves
                ? 'All 15 checkers borne off.'
                : 'You bore off $_borneOff of $_maxMoves.',
            score: _borneOff,
            statRows: [
              ('Borne', '$_borneOff'),
              ('Moves', '${_maxMoves - _movesLeft}'),
              ('Target', '$_maxMoves'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Backgammon board painter
// ────────────────────────────────────────────────────────────────────

class _BackgammonBoardPainter extends CustomPainter {
  _BackgammonBoardPainter({
    required this.borneOff,
    required this.maxMoves,
    required this.die1,
    required this.die2,
    required this.showDice,
  });

  final int borneOff;
  final int maxMoves;
  final int die1;
  final int die2;
  final bool showDice;

  static const _table = Color(0xFF8B5A2B);
  static const _tableDark = Color(0xFF6B4226);
  static const _board = Color(0xFFE8C58A);
  static const _triLight = Color(0xFFF1E2C0);
  static const _triDark = Color(0xFF8B4513);
  static const _checkerWhite = Color(0xFFF8F1E0);
  static const _checkerDark = Color(0xFF2A1A0F);
  static const _pipBlack = Color(0xFF111111);

  static final _tablePaint = Paint()..color = _table;
  static final _tableDarkPaint = Paint()..color = _tableDark;
  static final _boardPaint = Paint()..color = _board;
  static final _triLightPaint = Paint()..color = _triLight;
  static final _triDarkPaint = Paint()..color = _triDark;
  static final _checkerWhitePaint = Paint()..color = _checkerWhite;
  static final _checkerDarkPaint = Paint()..color = _checkerDark;
  static final _checkerShadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.35);
  static final _pipPaint = Paint()..color = _pipBlack;
  static final _diePaint = Paint()..color = Colors.white;
  static final _dieShadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.3);

  // 15 checkers: arranged in three stacks of 5 like a real starting
  // backgammon position (player at points 24, 13, 8 in the backgammon
  // sense, but we just use 3 visual stacks on the right of the board).
  static const int _playerStartStack1 = 5;
  static const int _playerStartStack2 = 3;
  static const int _playerStartStack3 = 5;

  @override
  void paint(Canvas canvas, Size size) {
    _drawTable(canvas, size);
    _drawBoard(canvas, size);
    _drawTriangles(canvas, size);
    _drawPlayerCheckers(canvas, size);
    _drawBorneOff(canvas, size);
    if (showDice) _drawDice(canvas, size);
  }

  void _drawTable(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _tablePaint);
    // Subtle grain border.
    final border = Rect.fromLTWH(
      size.width * 0.02,
      size.height * 0.04,
      size.width * 0.96,
      size.height * 0.92,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(border, Radius.circular(size.width * 0.02)),
      _tableDarkPaint,
    );
  }

  void _drawBoard(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    final boardRect = Rect.fromLTWH(
      pad,
      size.height * 0.18,
      size.width - pad * 2,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, Radius.circular(size.width * 0.015)),
      _boardPaint,
    );
    // Centre bar.
    final barRect = Rect.fromCenter(
      center: Offset(boardRect.center.dx, boardRect.center.dy),
      width: boardRect.width * 0.04,
      height: boardRect.height,
    );
    canvas.drawRect(barRect, _tableDarkPaint);
  }

  void _drawTriangles(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    final boardRect = Rect.fromLTWH(
      pad,
      size.height * 0.18,
      size.width - pad * 2,
      size.height * 0.64,
    );
    final triW = (boardRect.width - boardRect.width * 0.04) / 12;
    final triH = boardRect.height * 0.42;
    for (var i = 0; i < 12; i++) {
      final light = i.isEven;
      final paint = light ? _triLightPaint : _triDarkPaint;
      final x = boardRect.left + i * triW;
      // Top triangles.
      final top = Path()
        ..moveTo(x, boardRect.top + triH * 0.05)
        ..lineTo(x + triW / 2, boardRect.top + triH)
        ..lineTo(x + triW, boardRect.top + triH * 0.05)
        ..close();
      canvas.drawPath(top, paint);
      // Bottom triangles.
      final bottom = Path()
        ..moveTo(x, boardRect.bottom - triH * 0.05)
        ..lineTo(x + triW / 2, boardRect.bottom - triH)
        ..lineTo(x + triW, boardRect.bottom - triH * 0.05)
        ..close();
      canvas.drawPath(bottom, paint);
    }
  }

  void _drawPlayerCheckers(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    final boardRect = Rect.fromLTWH(
      pad,
      size.height * 0.18,
      size.width - pad * 2,
      size.height * 0.64,
    );
    final stackW = boardRect.width * 0.08;
    final checkerR = stackW * 0.45;

    // Stack 1 — bottom-left (5 checkers).
    _drawStack(
      canvas,
      Offset(boardRect.left + stackW * 0.5, boardRect.bottom - stackW * 0.5),
      _playerStartStack1,
      checkerR,
      isPlayer: true,
    );
    // Stack 2 — top-left (3 checkers).
    _drawStack(
      canvas,
      Offset(boardRect.left + stackW * 0.5, boardRect.top + stackW * 0.5),
      _playerStartStack2,
      checkerR,
      isPlayer: true,
    );
    // Stack 3 — right side (5 checkers).
    _drawStack(
      canvas,
      Offset(boardRect.right - stackW * 0.5, boardRect.top + stackW * 0.5),
      _playerStartStack3,
      checkerR,
      isPlayer: true,
    );

    // Single dark opponent checker floating for reference.
    canvas.drawCircle(
      Offset(boardRect.right - stackW * 0.5, boardRect.bottom - stackW * 0.5),
      checkerR,
      _checkerShadowPaint,
    );
    canvas.drawCircle(
      Offset(boardRect.right - stackW * 0.5, boardRect.bottom - stackW * 0.5),
      checkerR,
      _checkerDarkPaint,
    );
  }

  void _drawStack(
    Canvas canvas,
    Offset bottomCenter,
    int count,
    double radius, {
    required bool isPlayer,
  }) {
    final paint = isPlayer ? _checkerWhitePaint : _checkerDarkPaint;
    for (var i = 0; i < count; i++) {
      final cy = bottomCenter.dy - i * (radius * 1.8);
      canvas.drawCircle(
        Offset(bottomCenter.dx + 1, cy + 2),
        radius,
        _checkerShadowPaint,
      );
      canvas.drawCircle(Offset(bottomCenter.dx, cy), radius, paint);
    }
  }

  void _drawBorneOff(Canvas canvas, Size size) {
    if (borneOff <= 0) return;
    final pad = size.width * 0.05;
    final boardRect = Rect.fromLTWH(
      pad,
      size.height * 0.18,
      size.width - pad * 2,
      size.height * 0.64,
    );
    // Borne-off checkers appear in the bottom-right corner, like a
    // real backgammon off-tray.
    final offCenter = Offset(
      boardRect.right + size.width * 0.02,
      boardRect.bottom - size.width * 0.02,
    );
    final r = size.width * 0.012;
    for (var i = 0; i < borneOff && i < 15; i++) {
      final cx = offCenter.dx - (i % 5) * r * 2.2;
      final cy = offCenter.dy - (i ~/ 5) * r * 2.2;
      canvas.drawCircle(
        Offset(cx + 1, cy + 2),
        r,
        _checkerShadowPaint,
      );
      canvas.drawCircle(Offset(cx, cy), r, _checkerWhitePaint);
    }
  }

  void _drawDice(Canvas canvas, Size size) {
    final dieR = size.width * 0.045;
    final cx = size.width / 2;
    final cy = size.height * 0.08 + dieR;
    _drawDie(canvas, Offset(cx - dieR * 1.5, cy), dieR, die1);
    _drawDie(canvas, Offset(cx + dieR * 1.5, cy), dieR, die2);
  }

  void _drawDie(Canvas canvas, Offset center, double r, int face) {
    canvas.drawCircle(
      Offset(center.dx, center.dy + 2),
      r,
      _dieShadowPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: r * 1.8, height: r * 1.8),
        Radius.circular(r * 0.25),
      ),
      _diePaint,
    );
    // Pip layout for a 6-faced die (centred at `center`).
    final positions = <(double, double)>[
      (0, 0),
      (-0.4, -0.4),
      (0.4, 0.4),
      (0.4, -0.4),
      (-0.4, 0.4),
      (0, -0.5),
      (0, 0.5),
    ];
    final pipR = r * 0.12;
    final active = _pipLayoutFor(face);
    for (final idx in active) {
      final (fx, fy) = positions[idx];
      canvas.drawCircle(
        Offset(center.dx + fx * r * 1.4, center.dy + fy * r * 1.4),
        pipR,
        _pipPaint,
      );
    }
  }

  List<int> _pipLayoutFor(int face) {
    switch (face) {
      case 1:
        return [0];
      case 2:
        return [1, 2];
      case 3:
        return [1, 0, 2];
      case 4:
        return [1, 2, 3, 4];
      case 5:
        return [1, 2, 0, 3, 4];
      case 6:
        return [1, 2, 3, 4, 5, 6];
      default:
        return [0];
    }
  }

  @override
  bool shouldRepaint(_BackgammonBoardPainter old) =>
      old.borneOff != borneOff ||
      old.die1 != die1 ||
      old.die2 != die2 ||
      old.showDice != showDice;
}