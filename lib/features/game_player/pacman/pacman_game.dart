import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../games/game_widgets.dart';
import '../../games/mini_game.dart';
import '../../games/widgets/game_flow_overlays.dart';

/// Pac-Man — single-screen swipe-to-navigate maze chase in the
/// "Pool / Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: top-down blue maze with yellow pellets and
/// four coloured ghosts. Swipe up/down/left/right to change
/// direction. Eat all pellets to win — score 200 points.
///
/// Phases: `start → play → win → trophy`.
class PacmanGame extends MiniGame {
  const PacmanGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// Kept for dispatcher back-compat.
  final int level;

  @override
  State<PacmanGame> createState() => _PacmanState();
}

enum _PcPhase { start, play, win, trophy }

enum _PcDir { up, down, left, right }

const _kMaze = [
  '1111111111111111111',
  '1000000000110000001',
  '1011010110101101011',
  '1000000000000000001',
  '1010111011111011101',
  '1000000000110000001',
  '1111011100101110111',
  '1000000000000000001',
  '1110111011111011101',
  '0000110000100011000',
  '1110111011111011101',
  '1000000000000000001',
  '1010111011111011101',
  '1000000000110000001',
  '1011010110101101011',
  '1000000000000000001',
  '1011010110101101011',
  '1000000000000000001',
  '1111111111111111111',
];

class _PcGhost {
  _PcGhost(this.r, this.c, this.color);
  int r;
  int c;
  Color color;
}

class _PacmanState extends MiniGameState<PacmanGame>
    with SingleTickerProviderStateMixin {
  static const int _rows = 19;
  static const int _cols = 19;
  static const int _targetScore = 200;

  /// Public aliases so the painter can reference the grid dimensions.
  static const int gridRows = _rows;
  static const int gridCols = _cols;

  late final Ticker _ticker;
  late List<List<int>> _grid; // 1=wall, 0=pellet
  int _pR = 1, _pC = 1;
  _PcDir _pDir = _PcDir.right;
  _PcDir _pNext = _PcDir.right;
  int _score = 0;
  int _movesLeft = 30;
  double _ticksPerMove = 0;
  int _mouthFrame = 0;
  _PcPhase _phase = _PcPhase.start;
  final List<_PcGhost> _ghosts = [];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Score 0  •  Target $_targetScore');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats('Score $_score  •  Moves Left $_movesLeft');
  }

  void _buildLevel() {
    _grid = List.generate(_rows, (r) {
      return List.generate(_cols, (c) {
        return _kMaze[r][c] == '1' ? 1 : 0;
      });
    });
    _pR = 1;
    _pC = 1;
    _pDir = _PcDir.right;
    _pNext = _PcDir.right;
    _score = 0;
    _movesLeft = 30;
    _ticksPerMove = 0.0;
    _ghosts.clear();
    _ghosts.add(_PcGhost(9, 9, const Color(0xFFEF4444)));
    _ghosts.add(_PcGhost(9, 10, const Color(0xFFF472B6)));
    _ghosts.add(_PcGhost(10, 9, const Color(0xFF22D3EE)));
    _ghosts.add(_PcGhost(10, 10, const Color(0xFFFACC15)));
  }

  void _setDir(_PcDir d) {
    _pNext = d;
  }

  bool _canMove(int r, int c) {
    if (r < 0 || r >= _rows || c < 0 || c >= _cols) return false;
    return _grid[r][c] != 1;
  }

  void _stepPlayer() {
    if (_canMove(_pR + _dDr(_pNext), _pC + _dDc(_pNext))) {
      _pDir = _pNext;
    }
    if (_canMove(_pR + _dDr(_pDir), _pC + _dDc(_pDir))) {
      _pR += _dDr(_pDir);
      _pC += _dDc(_pDir);
      if (_grid[_pR][_pC] == 0) {
        _grid[_pR][_pC] = 2;
        _score += 10;
      }
    }
  }

  int _dDr(_PcDir d) {
    switch (d) {
      case _PcDir.up:
        return -1;
      case _PcDir.down:
        return 1;
      case _PcDir.left:
      case _PcDir.right:
        return 0;
    }
  }

  int _dDc(_PcDir d) {
    switch (d) {
      case _PcDir.left:
        return -1;
      case _PcDir.right:
        return 1;
      case _PcDir.up:
      case _PcDir.down:
        return 0;
    }
  }

  void _stepGhosts() {
    for (final g in _ghosts) {
      // Random walk with a bias toward the player.
      final dirs = _PcDir.values.toList()..shuffle(Random());
      _PcDir? best;
      int bestDist = 1 << 30;
      for (final d in dirs) {
        final nr = g.r + _dDr(d);
        final nc = g.c + _dDc(d);
        if (!_canMove(nr, nc)) continue;
        final dist = (nr - _pR).abs() + (nc - _pC).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = d;
        }
      }
      if (best != null) {
        g.r += _dDr(best);
        g.c += _dDc(best);
      }
    }
  }

  void _tick(Duration elapsed) {
    if (_phase != _PcPhase.play) return;
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    setState(() {
      _mouthFrame = (_mouthFrame + 1) % 16;
      _ticksPerMove += dt * 8;
      while (_ticksPerMove >= 1) {
        _ticksPerMove -= 1;
        _stepPlayer();
        _stepGhosts();
        _movesLeft--;
        // Ghost collision.
        for (final g in _ghosts) {
          if (g.r == _pR && g.c == _pC) {
            _endGame(won: false);
            return;
          }
        }
        // Pellet check.
        if (!_hasPellets()) {
          _endGame(won: true);
          return;
        }
        if (_movesLeft <= 0) {
          _endGame(won: false);
          return;
        }
      }
    });
    _refreshHud();
  }

  bool _hasPellets() {
    for (final row in _grid) {
      for (final c in row) {
        if (c == 0) return true;
      }
    }
    return false;
  }

  void _endGame({required bool won}) {
    if (_phase != _PcPhase.play) return;
    haptic(won ? HapticFeedbackType.heavy : HapticFeedbackType.selection);
    reportScore(_score);
    reportStats(won ? 'All dots eaten!' : 'Game over');
    reportGameOver();
    setState(() {
      _phase = won ? _PcPhase.win : _PcPhase.trophy;
    });
  }

  void _onPlay() {
    setState(() {
      _phase = _PcPhase.play;
      _buildLevel();
      _last = Duration.zero;
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _PcPhase.start;
      _score = 0;
    });
    _refreshHud();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _PcPhase.trophy;
    });
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, c) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final dx = d.delta.dx;
                    final dy = d.delta.dy;
                    if (dx.abs() < 4 && dy.abs() < 4) return;
                    if (dx.abs() > dy.abs()) {
                      _setDir(dx > 0 ? _PcDir.right : _PcDir.left);
                    } else {
                      _setDir(dy > 0 ? _PcDir.down : _PcDir.up);
                    }
                  },
                  child: CustomPaint(
                    painter: _PcPainter(
                      grid: _grid,
                      pR: _pR,
                      pC: _pC,
                      pDir: _pDir,
                      ghosts: _ghosts,
                      mouthFrame: _mouthFrame,
                    ),
                    size: Size(c.maxWidth, c.maxHeight),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _PcPhase.start)
          GameStartOverlay(
            title: 'PAC-MAN',
            subtitle: 'Eat all the dots\nand avoid the ghosts!',
            youScore: 0,
            targetScore: _targetScore,
            instruction:
                'Swipe up/down/left/right to change direction. Eat every pellet to win — reach 200 points.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _PcPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'ALL DOTS!',
            scoreValue: _score,
            scoreLabel: 'Pac Score',
            statRows: [
              ('Moves', '${30 - _movesLeft}/30'),
              ('Ghosts', '${_ghosts.length}'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _PcPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _score >= _targetScore ? 'Great Job!' : 'Keep Going!',
            subtitle: _score >= _targetScore
                ? 'You cleared the maze.'
                : 'Try again — eat every dot!',
            score: _score,
            statRows: [
              ('Score', '$_score'),
              ('Moves', '${30 - _movesLeft}'),
              ('Target', '$_targetScore'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _PcPhase.play)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GamePlayHud(
              youText: 'Score $_score',
              counterText: 'Moves Left $_movesLeft',
              onPause: null,
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Maze painter
// ────────────────────────────────────────────────────────────────────

class _PcPainter extends CustomPainter {
  _PcPainter({
    required this.grid,
    required this.pR,
    required this.pC,
    required this.pDir,
    required this.ghosts,
    required this.mouthFrame,
  });

  static const _rows = _PacmanState.gridRows;
  static const _cols = _PacmanState.gridCols;

  final List<List<int>> grid;
  final int pR;
  final int pC;
  final _PcDir pDir;
  final List<_PcGhost> ghosts;
  final int mouthFrame;

  static const _wall = Color(0xFF1E40AF);
  static const _wallDark = Color(0xFF1E3A8A);
  static const _floor = Color(0xFF000000);
  static const _floorAlt = Color(0xFF0A0A0A);
  static const _pellet = Color(0xFFFDE68A);
  static const _pac = Color(0xFFFACC15);

  @override
  void paint(Canvas canvas, Size size) {
    final maxSide = size.width < size.height ? size.width : size.height;
    final boardSize = (maxSide * 0.95).clamp(240.0, 460.0);
    final cw = boardSize / _cols;
    final ch = boardSize / _rows;
    final ox = (size.width - boardSize) / 2;
    final oy = (size.height - boardSize) / 2;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final rect = Rect.fromLTWH(ox + c * cw, oy + r * ch, cw, ch);
        if (grid[r][c] == 1) {
          canvas.drawRect(rect, Paint()..color = _wall);
          canvas.drawRect(
            rect,
            Paint()
              ..color = _wallDark
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        } else {
          canvas.drawRect(
            rect,
            Paint()
              ..color =
                  (r + c).isEven ? _floor : _floorAlt,
          );
          if (grid[r][c] == 0) {
            canvas.drawCircle(
              Offset(rect.center.dx, rect.center.dy),
              cw * 0.18,
              Paint()..color = _pellet,
            );
          }
        }
      }
    }

    // Ghosts.
    for (final g in ghosts) {
      final cx = ox + g.c * cw + cw / 2;
      final cy = oy + g.r * ch + ch / 2;
      final r = (cw * 0.42).clamp(8.0, 18.0);
      canvas.drawCircle(
        Offset(cx, cy + 1),
        r,
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );
      // Body.
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: r * 2,
        height: r * 2,
      );
      canvas.drawArc(rect, pi, pi, true, Paint()..color = g.color);
      // Skirt.
      final skirt = Path()
        ..moveTo(cx - r, cy)
        ..lineTo(cx - r, cy + r * 0.55)
        ..lineTo(cx - r * 0.5, cy + r * 0.25)
        ..lineTo(cx, cy + r * 0.55)
        ..lineTo(cx + r * 0.5, cy + r * 0.25)
        ..lineTo(cx + r, cy + r * 0.55)
        ..lineTo(cx + r, cy)
        ..close();
      canvas.drawPath(skirt, Paint()..color = g.color);
      // Eyes.
      final eyeR = r * 0.30;
      canvas.drawCircle(
        Offset(cx - r * 0.35, cy - r * 0.05),
        eyeR,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.35, cy - r * 0.05),
        eyeR,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx - r * 0.35 + 2, cy - r * 0.05),
        eyeR * 0.45,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.35 + 2, cy - r * 0.05),
        eyeR * 0.45,
        Paint()..color = Colors.black,
      );
    }

    // Pac-Man.
    final px = ox + pC * cw + cw / 2;
    final py = oy + pR * ch + ch / 2;
    final pr = (cw * 0.42).clamp(8.0, 18.0);
    double startA;
    switch (pDir) {
      case _PcDir.right:
        startA = 0;
        break;
      case _PcDir.down:
        startA = pi / 2;
        break;
      case _PcDir.left:
        startA = pi;
        break;
      case _PcDir.up:
        startA = 3 * pi / 2;
        break;
    }
    final mouth = (mouthFrame < 8) ? 0.45 : 0.12;
    final path = Path()
      ..moveTo(px, py)
      ..arcTo(
        Rect.fromCircle(center: Offset(px, py), radius: pr),
        startA + mouth,
        2 * pi - 2 * mouth,
        false,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = _pac);
  }

  @override
  bool shouldRepaint(_PcPainter old) =>
      old.pR != pR ||
      old.pC != pC ||
      old.pDir != pDir ||
      old.ghosts != ghosts ||
      old.mouthFrame != mouthFrame ||
      !_gridEq(old.grid, grid);

  static bool _gridEq(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var r = 0; r < a.length; r++) {
      if (a[r].length != b[r].length) return false;
      for (var c = 0; c < a[r].length; c++) {
        if (a[r][c] != b[r][c]) return false;
      }
    }
    return true;
  }
}
