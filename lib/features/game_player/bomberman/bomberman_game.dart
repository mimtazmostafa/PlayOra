import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../games/game_widgets.dart';
import '../../games/mini_game.dart';
import '../../games/widgets/game_flow_overlays.dart';

/// Bomberman — single-screen top-down maze-bomb game in the "Pool /
/// Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: green grid maze with grey walls and brown
/// crates. Player swipes to move, taps to drop a bomb. Crates explode
/// into points, enemies go down with bigger scores. Defeat all 5
/// enemies to win.
///
/// Phases: `start → play → win → trophy`.
class BombermanGame extends MiniGame {
  const BombermanGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// Kept for dispatcher back-compat.
  final int level;

  @override
  State<BombermanGame> createState() => _BombermanState();
}

enum _BmPhase { start, play, win, trophy }

enum _BmCell { empty, wall, block }

enum _BmDir { up, down, left, right }

class _BmBot {
  _BmBot(this.r, this.c);
  int r;
  int c;
}

class _BmBomb {
  _BmBomb(this.r, this.c);
  int r;
  int c;
  double fuse = 30; // ticks until explode
}

class _BmFlame {
  _BmFlame(this.r, this.c);
  int r;
  int c;
  double ttl = 10;
}

class _BombermanState extends MiniGameState<BombermanGame>
    with SingleTickerProviderStateMixin {
  static const int _rows = 9;
  static const int _cols = 13;
  static const int _enemyTarget = 5;

  /// Public aliases so the painter can reference the grid dimensions.
  static const int gridRows = _rows;
  static const int gridCols = _cols;

  late final Ticker _ticker;
  final Random _rng = Random();

  late List<List<_BmCell>> _grid;
  int _pR = 1, _pC = 1;
  final List<_BmBot> _bots = [];
  final List<_BmBomb> _bombs = [];
  final List<_BmFlame> _flames = [];
  int _score = 0;
  int _movesLeft = 60;
  _BmPhase _phase = _BmPhase.start;
  Duration _last = Duration.zero;

  double _boardW = 0;
  double _boardH = 0;

  @override
  void initState() {
    super.initState();
    _generateLevel();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Enemies ${_bots.length}/$_enemyTarget  •  Moves Left $_movesLeft');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshHud() {
    reportScore(_score);
    final alive = _bots.where((b) => _isAlive(b)).length;
    reportStats('Enemies $alive/$_enemyTarget  •  Moves Left $_movesLeft');
  }

  bool _isAlive(_BmBot b) {
    return !_flames.any((f) => f.r == b.r && f.c == b.c);
  }

  void _generateLevel() {
    _grid = List.generate(_rows, (_) => List.filled(_cols, _BmCell.empty));
    // Outer walls.
    for (var i = 0; i < _rows; i++) {
      _grid[i][0] = _BmCell.wall;
      _grid[i][_cols - 1] = _BmCell.wall;
    }
    for (var j = 0; j < _cols; j++) {
      _grid[0][j] = _BmCell.wall;
      _grid[_rows - 1][j] = _BmCell.wall;
    }
    // Inner walls.
    for (var r = 2; r < _rows - 1; r += 2) {
      for (var c = 2; c < _cols - 1; c += 2) {
        _grid[r][c] = _BmCell.wall;
      }
    }
    // Crates.
    for (var r = 1; r < _rows - 1; r++) {
      for (var c = 1; c < _cols - 1; c++) {
        if (_grid[r][c] == _BmCell.empty && (r != 1 || c != 1)) {
          if (_rng.nextDouble() < 0.45) {
            _grid[r][c] = _BmCell.block;
          }
        }
      }
    }
    _pR = 1;
    _pC = 1;
    _bots.clear();
    _bombs.clear();
    _flames.clear();
    _movesLeft = 60;
    _score = 0;
    // Spawn bots in random empty cells.
    final free = <List<int>>[];
    for (var r = 1; r < _rows - 1; r++) {
      for (var c = 1; c < _cols - 1; c++) {
        if (_grid[r][c] == _BmCell.empty) free.add([r, c]);
      }
    }
    free.shuffle(_rng);
    for (var i = 0; i < _enemyTarget && i < free.length; i++) {
      _bots.add(_BmBot(free[i][0], free[i][1]));
    }
  }

  bool _isWalkable(int r, int c) {
    if (r < 0 || r >= _rows || c < 0 || c >= _cols) return false;
    if (_grid[r][c] != _BmCell.empty) return false;
    for (final b in _bombs) {
      if (b.r == r && b.c == c) return false;
    }
    return true;
  }

  void _move(_BmDir d) {
    if (_phase != _BmPhase.play) return;
    if (_movesLeft <= 0) return;
    int nr = _pR, nc = _pC;
    switch (d) {
      case _BmDir.up:
        nr--;
        break;
      case _BmDir.down:
        nr++;
        break;
      case _BmDir.left:
        nc--;
        break;
      case _BmDir.right:
        nc++;
        break;
    }
    if (_isWalkable(nr, nc)) {
      setState(() {
        _pR = nr;
        _pC = nc;
        _movesLeft--;
      });
      haptic(HapticFeedbackType.selection);
      _refreshHud();
    }
  }

  void _placeBomb() {
    if (_phase != _BmPhase.play) return;
    for (final b in _bombs) {
      if (b.r == _pR && b.c == _pC) return;
    }
    setState(() {
      _bombs.add(_BmBomb(_pR, _pC));
    });
    haptic(HapticFeedbackType.medium);
  }

  void _tick(Duration elapsed) {
    if (_phase != _BmPhase.play) return;
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    setState(() {
      // Tick bombs.
      final toExplode = <_BmBomb>[];
      for (final b in _bombs) {
        b.fuse -= dt * 60;
        if (b.fuse <= 0) toExplode.add(b);
      }
      for (final b in toExplode) {
        _bombs.remove(b);
        _explode(b.r, b.c);
      }
      // Tick flames.
      _flames.removeWhere((f) {
        f.ttl -= dt * 60;
        return f.ttl <= 0;
      });
      // Player on flame?
      if (_flames.any((f) => f.r == _pR && f.c == _pC)) {
        _killPlayer();
      }
    });
    // Check win/lose.
    final alive = _bots.where((b) => _isAlive(b)).length;
    if (alive == 0) {
      _endGame(won: true);
    } else if (_movesLeft <= 0) {
      _endGame(won: false);
    }
    _refreshHud();
  }

  void _explode(int r, int c) {
    final dirs = [
      [0, 0],
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    for (final d in dirs) {
      final nr = r + d[0];
      final nc = c + d[1];
      if (nr < 0 || nr >= _rows || nc < 0 || nc >= _cols) continue;
      if (_grid[nr][nc] == _BmCell.wall) continue;
      if (_grid[nr][nc] == _BmCell.block) {
        _grid[nr][nc] = _BmCell.empty;
        _score += 5;
      }
      _flames.add(_BmFlame(nr, nc));
      // Kill any bot here.
      for (final bot in _bots) {
        if (bot.r == nr && bot.c == nc) {
          // Send bot to its own grave (i.e., remove next refresh).
          bot.r = -1;
          bot.c = -1;
          _score += 25;
        }
      }
    }
    haptic(HapticFeedbackType.heavy);
  }

  void _killPlayer() {
    if (_phase != _BmPhase.play) return;
    haptic(HapticFeedbackType.heavy);
    _endGame(won: false);
  }

  void _endGame({required bool won}) {
    if (_phase != _BmPhase.play) return;
    haptic(won ? HapticFeedbackType.heavy : HapticFeedbackType.selection);
    reportScore(_score);
    reportStats(
      won ? 'All enemies defeated' : 'Game over',
    );
    reportGameOver();
    setState(() {
      _phase = won ? _BmPhase.win : _BmPhase.trophy;
    });
  }

  void _onPlay() {
    setState(() {
      _phase = _BmPhase.play;
      _generateLevel();
      _last = Duration.zero;
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _BmPhase.start;
      _score = 0;
      _movesLeft = 60;
    });
    _refreshHud();
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _BmPhase.trophy;
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
                _boardW = c.maxWidth;
                _boardH = c.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _placeBomb,
                  onPanUpdate: (d) {
                    if (_phase != _BmPhase.play) return;
                    final dx = d.delta.dx;
                    final dy = d.delta.dy;
                    if (dx.abs() < 4 && dy.abs() < 4) return;
                    if (dx.abs() > dy.abs()) {
                      _move(dx > 0 ? _BmDir.right : _BmDir.left);
                    } else {
                      _move(dy > 0 ? _BmDir.down : _BmDir.up);
                    }
                  },
                  child: CustomPaint(
                    painter: _BmPainter(
                      grid: _grid,
                      pR: _pR,
                      pC: _pC,
                      bots: _bots,
                      bombs: _bombs,
                      flames: _flames,
                    ),
                    size: Size(_boardW, _boardH),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _BmPhase.start)
          GameStartOverlay(
            title: 'BOMBERMAN',
            subtitle: 'Place bombs and\ndefeat your enemies!',
            youScore: 0,
            targetScore: _enemyTarget,
            instruction:
                'Swipe to move. Tap to drop a bomb. Defeat all 5 enemies before running out of moves.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _BmPhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'ALL DEFEATED!',
            scoreValue: _score,
            scoreLabel: 'Bomb Score',
            statRows: [
              ('Moves', '${60 - _movesLeft}/60'),
              ('Crates', '$_score'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _BmPhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _bots.every((b) => !_isAlive(b))
                ? 'Great Job!'
                : 'Keep Going!',
            subtitle: _bots.every((b) => !_isAlive(b))
                ? 'You defeated every enemy.'
                : 'Try again — drop more bombs!',
            score: _score,
            statRows: [
              ('Score', '$_score'),
              ('Moves', '${60 - _movesLeft}'),
              ('Target', '$_enemyTarget'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _BmPhase.play)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GamePlayHud(
              youText: 'You ${_score ~/ 30}/$_enemyTarget',
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

class _BmPainter extends CustomPainter {
  _BmPainter({
    required this.grid,
    required this.pR,
    required this.pC,
    required this.bots,
    required this.bombs,
    required this.flames,
  });

  final List<List<_BmCell>> grid;
  final int pR;
  final int pC;
  final List<_BmBot> bots;
  final List<_BmBomb> bombs;
  final List<_BmFlame> flames;

  static const _rows = _BombermanState.gridRows;
  static const _cols = _BombermanState.gridCols;
  static const _ground = Color(0xFF166534);
  static const _groundDark = Color(0xFF14532D);
  static const _wall = Color(0xFF6B7280);
  static const _wallEdge = Color(0xFF374151);
  static const _block = Color(0xFFB45309);
  static const _blockEdge = Color(0xFF78350F);
  static const _player = Color(0xFF22D3EE);
  static const _bot = Color(0xFFEF4444);
  static const _bomb = Color(0xFF111111);
  static const _flame = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final maxSide = size.width < size.height ? size.width : size.height;
    final boardSize = (maxSide * 0.95).clamp(240.0, 460.0);
    final cw = boardSize / _cols;
    final ch = boardSize / _rows;
    final ox = (size.width - boardSize) / 2;
    final oy = (size.height - boardSize) / 2;

    // Outer background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.25),
    );

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final rect = Rect.fromLTWH(ox + c * cw, oy + r * ch, cw, ch);
        if (grid[r][c] == _BmCell.wall) {
          canvas.drawRect(rect, Paint()..color = _wall);
          canvas.drawRect(
            rect,
            Paint()
              ..color = _wallEdge
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        } else if (grid[r][c] == _BmCell.block) {
          canvas.drawRect(rect, Paint()..color = _block);
          canvas.drawRect(
            rect,
            Paint()
              ..color = _blockEdge
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
          // Wood grain.
          canvas.drawRect(
            Rect.fromLTWH(rect.left + 2, rect.top + 2, rect.width - 4, 2),
            Paint()..color = Colors.black.withValues(alpha: 0.3),
          );
        } else {
          canvas.drawRect(
            rect,
            Paint()
              ..color =
                  (r + c).isEven ? _ground : _groundDark,
          );
        }
      }
    }

    // Flames.
    for (final f in flames) {
      final rect = Rect.fromLTWH(
        ox + f.c * cw + 1,
        oy + f.r * ch + 1,
        cw - 2,
        ch - 2,
      );
      canvas.drawRect(rect, Paint()..color = _flame);
      canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.5));
    }

    // Bombs.
    for (final b in bombs) {
      final cx = ox + b.c * cw + cw / 2;
      final cy = oy + b.r * ch + ch / 2;
      final r = (cw * 0.32).clamp(6.0, 14.0);
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = _bomb);
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.3),
        r * 0.25,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
      // Fuse.
      canvas.drawLine(
        Offset(cx, cy - r),
        Offset(cx + 4, cy - r - 6),
        Paint()
          ..color = const Color(0xFFFFD166)
          ..strokeWidth = 2,
      );
    }

    // Bots.
    for (final b in bots) {
      if (!_isAlive(b)) continue;
      final cx = ox + b.c * cw + cw / 2;
      final cy = oy + b.r * ch + ch / 2;
      final r = (cw * 0.36).clamp(6.0, 14.0);
      canvas.drawCircle(
        Offset(cx, cy + 1),
        r,
        Paint()..color = Colors.black.withValues(alpha: 0.4),
      );
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = _bot);
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.1),
        r * 0.18,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.3, cy - r * 0.1),
        r * 0.18,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.1),
        r * 0.08,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.3, cy - r * 0.1),
        r * 0.08,
        Paint()..color = Colors.black,
      );
    }

    // Player.
    final pcx = ox + pC * cw + cw / 2;
    final pcy = oy + pR * ch + ch / 2;
    final pr = (cw * 0.36).clamp(6.0, 14.0);
    canvas.drawCircle(
      Offset(pcx, pcy + 1),
      pr,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawCircle(Offset(pcx, pcy), pr, Paint()..color = _player);
    canvas.drawCircle(
      Offset(pcx - pr * 0.3, pcy - pr * 0.1),
      pr * 0.18,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(pcx + pr * 0.3, pcy - pr * 0.1),
      pr * 0.18,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(pcx - pr * 0.3, pcy - pr * 0.1),
      pr * 0.08,
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      Offset(pcx + pr * 0.3, pcy - pr * 0.1),
      pr * 0.08,
      Paint()..color = Colors.black,
    );
  }

  bool _isAlive(_BmBot b) {
    return b.r >= 0 && b.c >= 0;
  }

  @override
  bool shouldRepaint(_BmPainter old) =>
      old.pR != pR ||
      old.pC != pC ||
      old.bots != bots ||
      old.bombs != bombs ||
      old.flames != flames ||
      !_gridEq(old.grid, grid);

  static bool _gridEq(List<List<_BmCell>> a, List<List<_BmCell>> b) {
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
