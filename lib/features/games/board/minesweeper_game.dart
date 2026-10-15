import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Minesweeper — single-screen tap-to-reveal puzzle in the redesigned
/// mini-game family.
///
/// Match the reference: 9×9 grid of tiles on a parchment-style
/// board. Tap to reveal; long-press to flag. Reveal all safe tiles
/// without detonating three mines to win.
///
/// Phases: `start → play → win → trophy`.
class MinesweeperGame extends MiniGame {
  const MinesweeperGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  final int level;

  @override
  State<MinesweeperGame> createState() => _MSGameState();
}

enum _MSPhase { start, play, win, trophy }

enum _TileState { hidden, revealed, flagged }

class _MSGameState extends MiniGameState<MinesweeperGame> {
  /// 9×9 grid (matches the reference's small grid look).
  static const int _rows = 9;
  static const int _cols = 9;

  /// Total mines per round.
  static const int _totalMines = 10;

  /// 3 detonations = lose.
  static const int _maxLives = 3;

  int _revealedSafe = 0;
  int _flags = 0;
  int _livesLeft = _maxLives;
  int _score = 0;
  _MSPhase _phase = _MSPhase.start;

  /// -1 = mine, 0 = empty, 1..8 = adjacent mine count.
  late List<List<int>> _grid;

  /// Per-tile state, mirrors [_grid] dimensions.
  late List<List<_TileState>> _states;

  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _newRound();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats(
        'Safe $_revealedSafe/${_rows * _cols - _totalMines}  •  Lives $_livesLeft',
      );
    });
  }

  void _newRound() {
    _grid = List.generate(_rows, (_) => List.filled(_cols, 0));
    _states = List.generate(
      _rows,
      (_) => List.filled(_cols, _TileState.hidden),
    );

    // Place mines, avoiding first-click-safe rule by deferring.
    final mines = <math.Point<int>>{};
    while (mines.length < _totalMines) {
      final p = math.Point(_rng.nextInt(_rows), _rng.nextInt(_cols));
      if (!mines.contains(p)) mines.add(p);
    }
    for (final m in mines) {
      _grid[m.x][m.y] = -1;
    }
    // Compute adjacency counts.
    for (var i = 0; i < _rows; i++) {
      for (var j = 0; j < _cols; j++) {
        if (_grid[i][j] == -1) continue;
        var count = 0;
        for (var di = -1; di <= 1; di++) {
          for (var dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            final ni = i + di;
            final nj = j + dj;
            if (ni < 0 || ni >= _rows || nj < 0 || nj >= _cols) continue;
            if (_grid[ni][nj] == -1) count++;
          }
        }
        _grid[i][j] = count;
      }
    }

    _revealedSafe = 0;
    _flags = 0;
    _livesLeft = _maxLives;
  }

  void _refreshHud() {
    reportScore(_score);
    final safeTotal = _rows * _cols - _totalMines;
    reportStats(
      'Safe $_revealedSafe/$safeTotal  •  Lives $_livesLeft',
    );
  }

  void _onPlay() {
    setState(() {
      _phase = _MSPhase.play;
      _score = 0;
      _newRound();
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _MSPhase.start;
      _score = 0;
      _newRound();
    });
    _refreshHud();
  }

  void _reveal(int i, int j) {
    if (_phase != _MSPhase.play) return;
    if (i < 0 || i >= _rows || j < 0 || j >= _cols) return;
    final s = _states[i][j];
    if (s == _TileState.revealed || s == _TileState.flagged) return;

    if (_grid[i][j] == -1) {
      _states[i][j] = _TileState.revealed;
      _livesLeft--;
      haptic(HapticFeedbackType.heavy);
      if (_livesLeft <= 0) {
        _revealAllMines();
        _endGame(win: false);
        return;
      }
      _refreshHud();
      if (mounted) setState(() {});
      return;
    }

    // Flood fill empty cells.
    final stack = <math.Point<int>>[math.Point(i, j)];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (p.x < 0 || p.x >= _rows || p.y < 0 || p.y >= _cols) continue;
      if (_states[p.x][p.y] == _TileState.revealed) continue;
      if (_states[p.x][p.y] == _TileState.flagged) continue;
      if (_grid[p.x][p.y] == -1) continue;
      _states[p.x][p.y] = _TileState.revealed;
      _revealedSafe++;
      if (_grid[p.x][p.y] == 0) {
        for (var di = -1; di <= 1; di++) {
          for (var dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            stack.add(math.Point(p.x + di, p.y + dj));
          }
        }
      }
    }
    _score += 5;
    haptic(HapticFeedbackType.light);
    _refreshHud();

    final safeTotal = _rows * _cols - _totalMines;
    if (_revealedSafe >= safeTotal) {
      _endGame(win: true);
    } else {
      if (mounted) setState(() {});
    }
  }

  void _toggleFlag(int i, int j) {
    if (_phase != _MSPhase.play) return;
    final s = _states[i][j];
    if (s == _TileState.revealed) return;
    setState(() {
      if (s == _TileState.hidden) {
        _states[i][j] = _TileState.flagged;
        _flags++;
      } else {
        _states[i][j] = _TileState.hidden;
        _flags--;
      }
    });
    haptic(HapticFeedbackType.selection);
    _refreshHud();
  }

  void _revealAllMines() {
    for (var i = 0; i < _rows; i++) {
      for (var j = 0; j < _cols; j++) {
        if (_grid[i][j] == -1) _states[i][j] = _TileState.revealed;
      }
    }
  }

  void _endGame({required bool win}) {
    reportGameOver();
    if (mounted) {
      setState(() {
        _phase = win ? _MSPhase.win : _MSPhase.trophy;
      });
    }
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _MSPhase.trophy;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: GestureDetector(
              onTapUp: (d) {
                final cell = _cellFromLocal(d.localPosition, context.size);
                if (cell != null) _reveal(cell.x, cell.y);
              },
              onLongPressStart: (d) {
                final cell = _cellFromLocal(d.localPosition, context.size);
                if (cell != null) _toggleFlag(cell.x, cell.y);
              },
              child: CustomPaint(
                painter: _MinesPainter(
                  grid: _grid,
                  states: _states,
                  rows: _rows,
                  cols: _cols,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        if (_phase == _MSPhase.start)
          GameStartOverlay(
            title: 'MINESWEEPER',
            subtitle: 'Reveal the safe\ntiles, avoid the mines!',
            youScore: _revealedSafe,
            targetScore: _rows * _cols - _totalMines,
            instruction:
                'Tap to reveal a tile. Long-press to flag a suspected mine. Avoid 3 detonations and clear all safe tiles to win.',
            illustration: const BoyCharacter(pose: BoyPose.waving),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _MSPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'FIELD CLEARED!',
            scoreValue: _score,
            scoreLabel: 'Clear Score',
            statRows: [
              ('Revealed', '$_revealedSafe/${_rows * _cols - _totalMines}'),
              ('Lives Left', '$_livesLeft/$_maxLives'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _MSPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _livesLeft > 0 ? 'Great Job!' : 'Keep Going!',
            subtitle: _livesLeft > 0
                ? 'You cleared the field.'
                : 'Try again — avoid the mines!',
            score: _score,
            statRows: [
              ('Revealed', '$_revealedSafe'),
              ('Flags', '$_flags'),
              ('Lives', '$_livesLeft'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }

  math.Point<int>? _cellFromLocal(Offset local, Size? size) {
    if (size == null) return null;
    final rect = _boardRect(size);
    if (!rect.contains(local)) return null;
    final cellW = rect.width / _cols;
    final cellH = rect.height / _rows;
    final i = ((local.dy - rect.top) / cellH).floor().clamp(0, _rows - 1);
    final j = ((local.dx - rect.left) / cellW).floor().clamp(0, _cols - 1);
    return math.Point<int>(i, j);
  }

  Rect _boardRect(Size size) {
    final side = math.min(size.width * 0.86, size.height * 0.6);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2 + 30;
    return Rect.fromLTWH(left, top, side, side);
  }
}

class _MinesPainter extends CustomPainter {
  _MinesPainter({
    required this.grid,
    required this.states,
    required this.rows,
    required this.cols,
  });

  final List<List<int>> grid;
  final List<List<_TileState>> states;
  final int rows;
  final int cols;

  static const _parchment = Color(0xFFFEE2C5);
  static const _hidden = Color(0xFF6B7280);
  static const _hiddenLight = Color(0xFF9CA3AF);
  static const _revealed = Color(0xFFFFF8E7);
  static const _flag = Color(0xFFEF4444);
  static const _mine = Color(0xFF111111);
  static const _frame = Color(0xFF4B5563);
  static const _num1 = Color(0xFF1D4ED8);
  static const _num2 = Color(0xFF16A34A);
  static const _num3 = Color(0xFFDC2626);
  static const _num4 = Color(0xFF7C3AED);
  static const _num5 = Color(0xFFB45309);
  static const _num6 = Color(0xFF0891B2);
  static const _num7 = Color(0xFF111827);
  static const _num8 = Color(0xFF4B5563);

  static final _parchmentPaint = Paint()..color = _parchment;
  static final _revealedPaint = Paint()..color = _revealed;
  static final _hiddenPaint = Paint()..color = _hidden;
  static final _hiddenLightPaint = Paint()..color = _hiddenLight;
  static final _frameStroke = Paint()
    ..color = _frame
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  static const Map<int, Color> _numColors = {
    1: _num1,
    2: _num2,
    3: _num3,
    4: _num4,
    5: _num5,
    6: _num6,
    7: _num7,
    8: _num8,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 24 || size.height < 24) return;
    final rect = _boardRect(size);
    final cellW = rect.width / cols;
    final cellH = rect.height / rows;

    // Parchment background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.width * 0.04),
      ),
      _parchmentPaint,
    );

    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        final r = Rect.fromLTWH(
          rect.left + j * cellW + 2,
          rect.top + i * cellH + 2,
          cellW - 4,
          cellH - 4,
        );
        final s = states[i][j];
        final v = grid[i][j];
        if (s == _TileState.revealed) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.12)),
            _revealedPaint,
          );
          if (v == -1) {
            _drawMine(canvas, r);
          } else if (v > 0) {
            _drawNumber(canvas, r, v);
          }
        } else if (s == _TileState.flagged) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.12)),
            _hiddenPaint,
          );
          _drawFlag(canvas, r);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.12)),
            _hiddenPaint,
          );
          // Bevel highlight (top-left).
          final bevel = Rect.fromLTWH(
            r.left + 2,
            r.top + 2,
            r.width - 4,
            r.height * 0.3,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(bevel, Radius.circular(cellW * 0.08)),
            _hiddenLightPaint,
          );
        }
      }
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.width * 0.04),
      ),
      _frameStroke,
    );
  }

  void _drawMine(Canvas canvas, Rect r) {
    final c = r.center;
    final radius = r.width * 0.32;
    canvas.drawCircle(c, radius, Paint()..color = _mine);
    // Spikes.
    final spike = Paint()
      ..color = _mine
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 2;
      canvas.drawLine(
        c,
        c + Offset(math.cos(a) * radius * 1.6, math.sin(a) * radius * 1.6),
        spike,
      );
    }
  }

  void _drawFlag(Canvas canvas, Rect r) {
    final c = r.center;
    final pole = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(c.dx, c.dy + r.height * 0.25),
      Offset(c.dx, c.dy - r.height * 0.3),
      pole,
    );
    final flag = Path()
      ..moveTo(c.dx, c.dy - r.height * 0.3)
      ..lineTo(c.dx + r.width * 0.3, c.dy - r.height * 0.18)
      ..lineTo(c.dx, c.dy - r.height * 0.05)
      ..close();
    canvas.drawPath(flag, Paint()..color = _flag);
  }

  void _drawNumber(Canvas canvas, Rect r, int n) {
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: TextStyle(
          color: _numColors[n] ?? Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: r.width * 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2),
    );
  }

  Rect _boardRect(Size size) {
    final side = math.min(size.width * 0.86, size.height * 0.6);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2 + 30;
    return Rect.fromLTWH(left, top, side, side);
  }

  @override
  bool shouldRepaint(_MinesPainter old) {
    if (old.rows != rows || old.cols != cols) return true;
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        if (grid[i][j] != old.grid[i][j]) return true;
        if (states[i][j] != old.states[i][j]) return true;
      }
    }
    return false;
  }
}
