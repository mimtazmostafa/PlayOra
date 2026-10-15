import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Maze Escape — single-screen tap-and-swipe maze in the "Pool /
/// Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: top-down stone castle maze with a golden
/// glowing exit door, blue-tinged entrance, green grass outside
/// walls, and 3 stars to collect.
///
/// Drag or swipe on the canvas to move cell-by-cell in cardinal
/// directions. Visiting a star cell collects it. Reaching the exit
/// cell in 10 moves wins.
///
/// Phases: `start → play → win → trophy`.
class MazeEscapeGame extends MiniGame {
  const MazeEscapeGame({super.key, required super.callbacks});

  @override
  State<MazeEscapeGame> createState() => _MazeEscapeGameState();
}

enum _MazePhase { start, play, win, trophy }

class _MazeEscapeGameState extends MiniGameState<MazeEscapeGame> {
  /// 10×10 maze (matching the reference's small grid look).
  static const int _size = 10;

  /// Maximum moves the player gets. Matches "Moves Left 10".
  static const int _maxMoves = 10;

  /// Number of stars to collect on the way to the exit.
  static const int _starCount = 3;

  int _movesLeft = _maxMoves;
  int _score = 0;
  int _starsCollected = 0;
  _MazePhase _phase = _MazePhase.start;

  /// 0 = open, 1 = wall.
  late List<List<int>> _maze;

  /// Star cells in the maze. Empty if collected.
  late List<math.Point<int>> _stars;

  /// Player cell.
  late math.Point<int> _player;
  late math.Point<int> _exit;

  /// Cached media-query size so the gesture handler can build a
  /// maze rect without needing the BuildContext.
  Size _lastSize = Size.zero;

  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _generateMaze();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Stars 0/$_starCount  •  Moves Left $_movesLeft');
    });
  }

  /// Build a maze with a guaranteed path from (0,0) to (_size-1,
  /// _size-1) using DFS, plus 3 star cells along the path.
  void _generateMaze() {
    final grid = List.generate(_size, (_) => List.filled(_size, 1));
    final visited = List.generate(_size, (_) => List.filled(_size, false));
    final stack = <math.Point<int>>[];
    final start = math.Point(0, 0);
    stack.add(start);
    visited[0][0] = true;
    grid[0][0] = 0;
    final dirs = [
      math.Point(0, 1),
      math.Point(1, 0),
      math.Point(0, -1),
      math.Point(-1, 0),
    ];
    while (stack.isNotEmpty) {
      final here = stack.last;
      final candidates = <math.Point<int>>[];
      for (final d in dirs) {
        final n = math.Point(here.x + d.x * 2, here.y + d.y * 2);
        if (n.x < 0 || n.x >= _size || n.y < 0 || n.y >= _size) continue;
        if (visited[n.x][n.y]) continue;
        candidates.add(n);
      }
      if (candidates.isEmpty) {
        stack.removeLast();
        continue;
      }
      final next = candidates[_rng.nextInt(candidates.length)];
      final wallBetween = math.Point(
        (here.x + next.x) ~/ 2,
        (here.y + next.y) ~/ 2,
      );
      grid[next.x][next.y] = 0;
      grid[wallBetween.x][wallBetween.y] = 0;
      visited[next.x][next.y] = true;
      stack.add(next);
    }
    _maze = grid;
    _player = math.Point(0, 0);
    _exit = math.Point(_size - 1, _size - 1);

    // Collect the path cells (BFS from start) and place 3 stars at
    // positions roughly 1/3, 2/3, and the last step before exit.
    final path = <math.Point<int>>[];
    final queue = <math.Point<int>>[start];
    final parent = <math.Point<int>, math.Point<int>?>{start: null};
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      path.add(cur);
      for (final d in dirs) {
        final n = math.Point(cur.x + d.x, cur.y + d.y);
        if (n.x < 0 || n.x >= _size || n.y < 0 || n.y >= _size) continue;
        if (parent.containsKey(n)) continue;
        if (_maze[n.x][n.y] != 0) continue;
        parent[n] = cur;
        queue.add(n);
      }
    }
    final exitPath = <math.Point<int>>[];
    math.Point<int>? node = _exit;
    while (node != null) {
      exitPath.add(node);
      final next = parent[node];
      node = next;
    }
    final reversedPath = exitPath.reversed.toList();
    _stars = [];
    // Pick star cells along the path. Guard clamp bounds — if the
    // path is very short, fall back to the start/exit neighbours.
    final lastIdx = reversedPath.length - 1;
    int safePick(double frac) {
      if (lastIdx <= 0) return 0;
      final idx = (lastIdx * frac).floor();
      return idx.clamp(1, lastIdx - 1).toInt();
    }

    final picks = <int>{
      safePick(0.33),
      safePick(0.66),
      safePick(1.0),
    };
    for (final idx in picks) {
      final c = reversedPath[idx];
      if (c == start || c == _exit) continue;
      if (_stars.contains(c)) continue;
      _stars.add(c);
    }
    while (_stars.length < _starCount && path.isNotEmpty) {
      final c = path[_rng.nextInt(path.length)];
      if (c == start || c == _exit) continue;
      if (_stars.contains(c)) continue;
      _stars.add(c);
    }
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats(
      'Stars $_starsCollected/$_starCount  •  Moves Left $_movesLeft',
    );
  }

  void _onPlay() {
    setState(() {
      _phase = _MazePhase.play;
      _movesLeft = _maxMoves;
      _starsCollected = 0;
      _player = math.Point(0, 0);
      _generateMaze();
    });
    _refreshHud();
  }

  bool _tryStep(int dx, int dy) {
    final nx = _player.x + dx;
    final ny = _player.y + dy;
    if (nx < 0 || nx >= _size || ny < 0 || ny >= _size) return false;
    if (_maze[nx][ny] != 0) return false;
    _player = math.Point(nx, ny);
    return true;
  }

  void _stepDirection(math.Point<int> dir) {
    if (_phase != _MazePhase.play) return;
    if (_movesLeft <= 0) return;
    if (!_tryStep(dir.x, dir.y)) return;
    if (_stars.contains(_player)) {
      _stars = _stars.where((s) => s != _player).toList();
      _starsCollected++;
      haptic(HapticFeedbackType.medium);
    } else {
      haptic(HapticFeedbackType.light);
    }
    setState(() {
      _movesLeft--;
    });
    _refreshHud();

    if (_player == _exit) {
      _score = _starsCollected * 20 + (_movesLeft * 5) + 100;
      haptic(HapticFeedbackType.heavy);
      reportGameOver();
      setState(() {
        _phase = _MazePhase.win;
      });
      return;
    }
    if (_movesLeft <= 0) {
      _score = _starsCollected * 20;
      _phase = _MazePhase.trophy;
      reportGameOver();
      if (mounted) setState(() {});
    }
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _MazePhase.trophy;
    });
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _MazePhase.start;
      _movesLeft = _maxMoves;
      _starsCollected = 0;
      _score = 0;
      _generateMaze();
    });
    _refreshHud();
  }

  /// Unified gesture handler — accepts a tap or pan position and
  /// steps one cell in the dominant direction (the maze only allows
  /// cardinal movement).
  void _onMazeGesture(Offset localPosition) {
    if (_phase != _MazePhase.play) return;
    final Rect rect = _mazeRect(_lastSize);
    final double diffX = localPosition.dx - rect.center.dx;
    final double diffY = localPosition.dy - rect.center.dy;
    int dx = 0;
    if (diffX > 0) {
      dx = 1;
    } else if (diffX < 0) {
      dx = -1;
    }
    int dy = 0;
    if (diffY > 0) {
      dy = 1;
    } else if (diffY < 0) {
      dy = -1;
    }
    if (dx.abs() > dy.abs()) {
      _stepDirection(math.Point(dx, 0));
    } else if (dy != 0) {
      _stepDirection(math.Point(0, dy));
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _lastSize = size;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) =>
                  _onMazeGesture(details.localPosition),
              onPanUpdate: (details) =>
                  _onMazeGesture(details.localPosition),
              child: CustomPaint(
                painter: _MazePainter(
                  maze: _maze,
                  size: _size,
                  player: _player,
                  exit: _exit,
                  stars: _stars,
                ),
                size: size,
              ),
            ),
          ),
        ),
        if (_phase == _MazePhase.start)
          GameStartOverlay(
            title: 'MAZE ESCAPE',
            subtitle: 'Find the exit,\nescape!',
            youScore: _starsCollected,
            targetScore: _starCount,
            instruction:
                'Swipe to move through the maze. Collect 3 stars and reach the exit in 10 moves.',
            illustration: const BoyCharacter(pose: BoyPose.walking),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _MazePhase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'YOU ESCAPED!',
            scoreValue: _score,
            scoreLabel: 'Escape Score',
            statRows: [
              ('Stars', '$_starsCollected/$_starCount'),
              ('Moves', '${_maxMoves - _movesLeft}/$_maxMoves'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _MazePhase.trophy)
          GameTrophyOverlay(
            iconData: Icons.emoji_events_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _starsCollected >= _starCount ? 'Great Job!' : 'Keep Going!',
            subtitle: _starsCollected >= _starCount
                ? 'You collected all stars and escaped.'
                : 'Try again — reach the exit before moves run out.',
            score: _score,
            statRows: [
              ('Stars', '$_starsCollected'),
              ('Moves', '${_maxMoves - _movesLeft}'),
              ('Target', '$_starCount'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }

  Rect _mazeRect(Size size) {
    final side = math.min(size.width * 0.86, size.height * 0.5);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    return Rect.fromLTWH(left, top, side, side);
  }
}

// ────────────────────────────────────────────────────────────────────
// Maze painter
// ────────────────────────────────────────────────────────────────────

class _MazePainter extends CustomPainter {
  _MazePainter({
    required this.maze,
    required this.size,
    required this.player,
    required this.exit,
    required this.stars,
  });

  final List<List<int>> maze;
  final int size;
  final math.Point<int> player;
  final math.Point<int> exit;
  final List<math.Point<int>> stars;

  static const _grass = Color(0xFF86EFAC);
  static const _stone = Color(0xFF6B7280);
  static const _stoneLight = Color(0xFF9CA3AF);
  static const _stoneEdge = Color(0xFF4B5563);
  static const _path = Color(0xFFFEE2C5);
  static const _doorGold = Color(0xFFFACC15);
  static const _doorGoldDark = Color(0xFFCA8A04);
  static const _doorGlow = Color(0xFFFFE066);
  static const _entrance = Color(0xFF60A5FA);
  static const _playerBlue = Color(0xFF1E3A8A);
  static const _playerLight = Color(0xFF60A5FA);
  static const _starGold = Color(0xFFFACC15);

  static final _grassPaint = Paint()..color = _grass;
  static final _stonePaint = Paint()..color = _stone;
  static final _stoneLightPaint = Paint()..color = _stoneLight;
  static final _stoneEdgePaint = Paint()
    ..color = _stoneEdge
    ..strokeWidth = 1;
  static final _pathPaint = Paint()..color = _path;
  static final _doorGoldPaint = Paint()..color = _doorGold;
  static final _doorGlowPaint = Paint()..color = _doorGlow;
  static final _entrancePaint = Paint()..color = _entrance;
  static final _playerPaint = Paint()..color = _playerBlue;
  static final _playerShinePaint = Paint()..color = _playerLight;
  static final _starPaint = Paint()..color = _starGold;
  static final _starShinePaint = Paint()..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    // Bail before paint math if the canvas hasn't been laid out yet —
    // guards against radius=0 / negative-rect throws on the first frame.
    if (size.width < 24 || size.height < 24) return;
    final mazeRect = _mazeRect(size);
    _drawGrass(canvas, mazeRect);
    _drawStoneCells(canvas, mazeRect);
    _drawPathOverlay(canvas, mazeRect);
    _drawStars(canvas, mazeRect);
    _drawExitDoor(canvas, mazeRect);
    _drawEntrance(canvas, mazeRect);
    _drawPlayer(canvas, mazeRect);
    _drawFrame(canvas, mazeRect);
  }

  Rect _mazeRect(Size size) {
    final side = math.min(size.width * 0.86, size.height * 0.5);
    final left = (size.width - side) / 2;
    final top = (size.height - side) / 2;
    return Rect.fromLTWH(left, top, side, side);
  }

  void _drawGrass(Canvas canvas, Rect rect) {
    final inflate = rect.inflate(20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inflate, Radius.circular(rect.width * 0.04)),
      _grassPaint,
    );
  }

  void _drawStoneCells(Canvas canvas, Rect rect) {
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    for (var i = 0; i < size; i++) {
      for (var j = 0; j < size; j++) {
        if (maze[i][j] != 1) continue;
        final r = Rect.fromLTWH(
          rect.left + j * cellW,
          rect.top + i * cellH,
          cellW,
          cellH,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.08)),
          _stonePaint,
        );
        // Highlight + edge.
        final highlight = Rect.fromLTWH(
          r.left,
          r.top,
          r.width,
          r.height * 0.3,
        );
        canvas.drawRect(highlight, _stoneLightPaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.08)),
          _stoneEdgePaint,
        );
      }
    }
  }

  void _drawPathOverlay(Canvas canvas, Rect rect) {
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    for (var i = 0; i < size; i++) {
      for (var j = 0; j < size; j++) {
        if (maze[i][j] != 0) continue;
        final r = Rect.fromLTWH(
          rect.left + j * cellW + 1,
          rect.top + i * cellH + 1,
          cellW - 2,
          cellH - 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(cellW * 0.18)),
          _pathPaint,
        );
      }
    }
  }

  void _drawStars(Canvas canvas, Rect rect) {
    if (stars.isEmpty) return;
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    for (final s in stars) {
      final c = Offset(
        rect.left + s.y * cellW + cellW / 2,
        rect.top + s.x * cellH + cellH / 2,
      );
      final r = cellW * 0.25;
      // Star shape (5-point simplified as a rounded star path).
      _drawStarShape(canvas, c, r);
    }
  }

  void _drawStarShape(Canvas canvas, Offset c, double r) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final isOuter = i.isEven;
      final radius = isOuter ? r : r * 0.45;
      final angle = (i * math.pi / points) - math.pi / 2;
      final pt = Offset(c.dx + radius * math.cos(angle), c.dy + radius * math.sin(angle));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _starPaint);
    canvas.drawCircle(
      Offset(c.dx - r * 0.2, c.dy - r * 0.2),
      r * 0.2,
      _starShinePaint,
    );
  }

  void _drawExitDoor(Canvas canvas, Rect rect) {
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    final c = Offset(
      rect.left + exit.y * cellW + cellW / 2,
      rect.top + exit.x * cellH + cellH / 2,
    );
    final r = cellW * 0.40;
    canvas.drawCircle(c, r * 1.3, _doorGlowPaint);
    canvas.drawCircle(c, r, _doorGoldPaint);
    // Door handle.
    canvas.drawCircle(
      Offset(c.dx + r * 0.3, c.dy),
      r * 0.15,
      Paint()..color = _doorGoldDark,
    );
  }

  void _drawEntrance(Canvas canvas, Rect rect) {
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    final c = Offset(
      rect.left + 0 * cellW + cellW / 2,
      rect.top + 0 * cellH + cellH / 2,
    );
    final r = cellW * 0.30;
    canvas.drawCircle(c, r, _entrancePaint);
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  void _drawPlayer(Canvas canvas, Rect rect) {
    final cellW = rect.width / size;
    final cellH = rect.height / size;
    final c = Offset(
      rect.left + player.y * cellW + cellW / 2,
      rect.top + player.x * cellH + cellH / 2,
    );
    final r = cellW * 0.32;
    canvas.drawCircle(
      Offset(c.dx + 1, c.dy + 2),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(c, r, _playerPaint);
    canvas.drawCircle(
      Offset(c.dx - r * 0.3, c.dy - r * 0.3),
      r * 0.25,
      _playerShinePaint,
    );
  }

  void _drawFrame(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(
      rect.inflate(4),
      Radius.circular(rect.width * 0.04),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _stoneEdge
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_MazePainter old) =>
      old.player != player ||
      old.exit != exit ||
      !_starsEqual(old.stars, stars) ||
      !_mazeEqual(old.maze, maze);

  static bool _starsEqual(List<math.Point<int>> a, List<math.Point<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mazeEqual(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }
}
