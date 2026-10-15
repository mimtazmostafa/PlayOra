import 'dart:math';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Snake Duel — ported from `downloaded_games/games/snake_duel/game.py`.
///
/// Two snakes share the same grid. First to crash loses.
/// Controls (2P mode):
///   * P1 (green) — Arrow keys
///   * P2 (blue)  — WASD
///
/// In vs-Bot mode P2 is AI with 3 difficulty levels:
///   * easy   — go toward food with 10% randomness
///   * medium — go toward food with safety check
///   * hard   — BFS to food, flood-fill fallback when no path
class SnakeDuelGame extends MiniGame {
  const SnakeDuelGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard bot (when AI mode on).
  final int level;

  @override
  State<SnakeDuelGame> createState() => _SnakeDuelGameState();
}

enum _SDDifficulty { easy, medium, hard }
enum _SDPhase { start, playing, paused, gameOver }

typedef _Dir = (int dx, int dy);

class _SnakeDuelGameState extends MiniGameState<SnakeDuelGame>
    with SingleTickerProviderStateMixin {
  static const int _cols = 24;
  static const int _rows = 18;
  static const Duration _moveDelay = Duration(milliseconds: 130);

  late final Ticker _ticker;
  DateTime _lastMove = DateTime.now();

  bool _isAi = true;
  late _SDDifficulty _botDiff;

  // Snakes (list of cells; head at index 0)
  List<Point<int>> _snake1 = [];
  List<Point<int>> _snake2 = [];
  _Dir _dir1 = (-1, 0);
  _Dir _nextDir1 = (-1, 0);
  _Dir _dir2 = (1, 0);
  _Dir _nextDir2 = (1, 0);
  Point<int> _food = const Point(0, 0);

  _SDPhase _phase = _SDPhase.start;
  int _score1 = 0;
  int _score2 = 0;
  Duration _stepDuration = _moveDelay;

  static const Color _bg = Color(0xFF0F0F1A);
  static const Color _wall = Color(0xFF28283C);
  static const Color _p1 = Color(0xFF32FF32);
  static const Color _p2 = Color(0xFF3296FF);
  static const Color _p1Head = Color(0xFF00C800);
  static const Color _p2Head = Color(0xFF0080FF);
  static const Color _foodCol = Color(0xFFFF3232);

  @override
  void initState() {
    super.initState();
    _botDiff = widget.level >= 3
        ? _SDDifficulty.hard
        : (widget.level >= 2 ? _SDDifficulty.medium : _SDDifficulty.easy);
    _resetGame();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _resetGame() {
    const startX1 = _cols - 6;
    const startY1 = _rows ~/ 2;
    _snake1 = [
      const Point(startX1, startY1),
      const Point(startX1 + 1, startY1),
      const Point(startX1 + 2, startY1),
    ];
    _dir1 = (-1, 0);
    _nextDir1 = (-1, 0);
    const startX2 = 5;
    const startY2 = _rows ~/ 2;
    _snake2 = [
      const Point(startX2, startY2),
      const Point(startX2 - 1, startY2),
      const Point(startX2 - 2, startY2),
    ];
    _dir2 = (1, 0);
    _nextDir2 = (1, 0);
    _food = _spawnFood();
    _phase = _SDPhase.start;
    _stepDuration = _moveDelay;
    _score1 = 0;
    _score2 = 0;
    // Defer host-state updates: _resetGame is called from initState
    // (during which the parent GameContainerScreen is still in its
    // first build phase). Calling reportScore/reportStats here would
    // fire setState on the host during build and crash with
    // "setState() or markNeedsBuild() called during build". The
    // post-frame callback runs after the build phase completes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reportScore(0);
      _updateStats();
    });
  }

  Point<int> _spawnFood() {
    final rng = Random();
    while (true) {
      final f = Point(rng.nextInt(_cols), rng.nextInt(_rows));
      if (!_snake1.contains(f) && !_snake2.contains(f)) return f;
    }
  }

  bool _onBoard(Point<int> p) =>
      p.x >= 0 && p.x < _cols && p.y >= 0 && p.y < _rows;

  void _onTick(Duration _) {
    if (_phase == _SDPhase.gameOver) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (_phase != _SDPhase.playing) {
      setState(() {});
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastMove) < _stepDuration) {
      setState(() {});
      return;
    }
    _lastMove = now;

    if (_isAi) {
      _nextDir2 = _getBotMove();
    }

    _dir1 = _nextDir1;
    _dir2 = _nextDir2;

    final head1 = Point(_snake1.first.x + _dir1.$1, _snake1.first.y + _dir1.$2);
    final head2 = Point(_snake2.first.x + _dir2.$1, _snake2.first.y + _dir2.$2);

    bool p1Dead = false;
    bool p2Dead = false;

    if (!_onBoard(head1)) p1Dead = true;
    if (!_onBoard(head2)) p2Dead = true;
    if (head1 == head2) {
      p1Dead = true;
      p2Dead = true;
    }
    if (_snake1.skip(1).contains(head1)) p1Dead = true;
    if (_snake2.skip(1).contains(head2)) p2Dead = true;
    if (_snake2.contains(head1)) p1Dead = true;
    if (_snake1.contains(head2)) p2Dead = true;

    if (p1Dead && p2Dead) {
      _finish(0);
      return;
    }
    if (p1Dead) {
      _score2++;
      _finish(2);
      return;
    }
    if (p2Dead) {
      _score1++;
      _finish(1);
      return;
    }

    _snake1.insert(0, head1);
    _snake2.insert(0, head2);

    final ate1 = head1 == _food;
    final ate2 = head2 == _food;
    if (ate1 || ate2) {
      haptic(HapticFeedbackType.medium);
      _food = _spawnFood();
      _stepDuration = Duration(
          milliseconds: max(50, (_stepDuration.inMilliseconds * 0.97).toInt()));
    }
    if (!ate1) _snake1.removeLast();
    if (!ate2) _snake2.removeLast();

    reportScore((_snake1.length + _snake2.length) * 10);
    _updateStats();
    setState(() {});
  }

  void _finish(int winner) {
    setState(() {
      _phase = _SDPhase.gameOver;
    });
    reportScore(
        (_score1 - _score2) * 200 + (winner == 1 ? 250 : (winner == 2 && !_isAi ? 250 : 0)));
    haptic(HapticFeedbackType.heavy);
    reportGameOver();
  }

  void _setDir1(_Dir d) {
    if ((d.$1, d.$2) == (-_dir1.$1, -_dir1.$2)) return;
    _nextDir1 = d;
  }

  void _setDir2(_Dir d) {
    if ((d.$1, d.$2) == (-_dir2.$1, -_dir2.$2)) return;
    _nextDir2 = d;
  }

  // ─── AI ──────────────────────────────────────────────────────────────

  bool _isSafe(int x, int y) {
    if (x < 0 || x >= _cols || y < 0 || y >= _rows) return false;
    final p = Point(x, y);
    if (_snake1.contains(p)) return false;
    if (_snake2.skip(1).contains(p)) return false;
    return true;
  }

  _Dir _getBotMove() {
    final allDirs = <_Dir>[
      (0, -1),
      (0, 1),
      (-1, 0),
      (1, 0),
    ];
    final possibleDirs = allDirs
        .where((d) =>
            (d.$1, d.$2) != (-_dir2.$1, -_dir2.$2))
        .toList();

    final head = _snake2.first;
    final food = _food;

    if (_botDiff == _SDDifficulty.easy) {
      final dx = food.x - head.x;
      final dy = food.y - head.y;
      _Dir bestDir;
      if (dx.abs() > dy.abs()) {
        bestDir = (dx > 0 ? 1 : -1, 0);
      } else {
        bestDir = (0, dy > 0 ? 1 : -1);
      }
      if (possibleDirs.contains(bestDir) &&
          Random().nextDouble() > 0.1) {
        return bestDir;
      }
      return possibleDirs.first;
    }

    final safeDirs = possibleDirs
        .where((d) => _isSafe(head.x + d.$1, head.y + d.$2))
        .toList();
    if (safeDirs.isEmpty) return possibleDirs.first;

    if (_botDiff == _SDDifficulty.medium) {
      var bestDir = safeDirs.first;
      var minDist = 1 << 30;
      for (final d in safeDirs) {
        final nx = head.x + d.$1;
        final ny = head.y + d.$2;
        final dist = (nx - food.x).abs() + (ny - food.y).abs();
        if (dist < minDist) {
          minDist = dist;
          bestDir = d;
        }
      }
      return bestDir;
    }

    // hard
    final queue = Queue<List<dynamic>>();
    queue.add([head, <_Dir>[]]);
    final visited = <Point<int>>{head};
    List<_Dir>? pathFound;
    while (queue.isNotEmpty) {
      final entry = queue.removeFirst();
      final curr = entry[0] as Point<int>;
      final path = entry[1] as List<_Dir>;
      if (curr == food) {
        pathFound = path;
        break;
      }
      for (final d in allDirs) {
        final nx = curr.x + d.$1;
        final ny = curr.y + d.$2;
        final np = Point(nx, ny);
        if (_isSafe(nx, ny) && !visited.contains(np)) {
          visited.add(np);
          queue.add([np, [...path, d]]);
        }
      }
    }
    if (pathFound != null && pathFound.isNotEmpty && safeDirs.contains(pathFound.first)) {
      return pathFound.first;
    }
    // Survival mode with flood-fill
    var bestDir = safeDirs.first;
    var maxSpace = -1;
    for (final d in safeDirs) {
      final space = _floodFill(head.x + d.$1, head.y + d.$2);
      if (space > maxSpace) {
        maxSpace = space;
        bestDir = d;
      }
    }
    return bestDir;
  }

  int _floodFill(int sx, int sy) {
    final queue = Queue<Point<int>>();
    queue.add(Point(sx, sy));
    final visited = <Point<int>>{Point(sx, sy)};
    var space = 0;
    while (queue.isNotEmpty && space < 100) {
      final curr = queue.removeFirst();
      space++;
      for (final d in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        final nx = curr.x + d.$1;
        final ny = curr.y + d.$2;
        if (nx >= 0 && nx < _cols && ny >= 0 && ny < _rows) {
          final np = Point(nx, ny);
          if (!visited.contains(np) &&
              !_snake1.contains(np) &&
              !_snake2.skip(1).contains(np)) {
            visited.add(np);
            queue.add(np);
          }
        }
      }
    }
    return space;
  }

  void _updateStats() {
    final turn = _phase == _SDPhase.gameOver
        ? 'Game over'
        : 'P1 ${_snake1.length} · P2 ${_snake2.length}';
    reportStats(turn);
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_phase == _SDPhase.gameOver &&
            event.logicalKey == LogicalKeyboardKey.space) {
          _resetGame();
          setState(() {
            _phase = _SDPhase.playing;
          });
          return KeyEventResult.handled;
        }
        if (_phase == _SDPhase.start && event.logicalKey == LogicalKeyboardKey.space) {
          setState(() {
            _phase = _SDPhase.playing;
            _lastMove = DateTime.now();
          });
          return KeyEventResult.handled;
        }
        if (_phase == _SDPhase.playing) {
          if (event.logicalKey == LogicalKeyboardKey.space) {
            setState(() => _phase = _SDPhase.paused);
            return KeyEventResult.handled;
          }
          // P1 - Arrows
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) _setDir1((0, -1));
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) _setDir1((0, 1));
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _setDir1((-1, 0));
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) _setDir1((1, 0));
          // P2 - WASD
          if (event.logicalKey == LogicalKeyboardKey.keyW) _setDir2((0, -1));
          if (event.logicalKey == LogicalKeyboardKey.keyS) _setDir2((0, 1));
          if (event.logicalKey == LogicalKeyboardKey.keyA) _setDir2((-1, 0));
          if (event.logicalKey == LogicalKeyboardKey.keyD) _setDir2((1, 0));
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: _bg,
        child: SafeArea(
          child: Column(
            children: [
              // Top HUD removed — host GameContainerScreen provides it.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final cellW = (c.maxWidth - 8) / _cols;
                    final cellH = (c.maxHeight - 8) / _rows;
                    final cell = min(cellW, cellH).clamp(8.0, 32.0);
                    return Center(
                      child: SizedBox(
                        width: cell * _cols,
                        height: cell * _rows,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            if (_phase == _SDPhase.start) {
                              setState(() => _phase = _SDPhase.playing);
                            } else if (_phase == _SDPhase.gameOver) {
                              _resetGame();
                              setState(() => _phase = _SDPhase.playing);
                            }
                          },
                          child: CustomPaint(
                            size: Size(cell * _cols, cell * _rows),
                            painter: _SnakeDuelPainter(
                              cell: cell,
                              cols: _cols,
                              rows: _rows,
                              snake1: _snake1,
                              snake2: _snake2,
                              dir1: _dir1,
                              dir2: _dir2,
                              food: _food,
                              p1Color: _p1,
                              p1HeadColor: _p1Head,
                              p2Color: _p2,
                              p2HeadColor: _p2Head,
                              foodColor: _foodCol,
                              wallColor: _wall,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF06060F),
      child: Row(
        children: [
          ToggleButtons(
            isSelected: [!_isAi, _isAi],
            onPressed: (i) {
              setState(() {
                _isAi = i == 1;
              });
              _resetGame();
            },
            constraints: const BoxConstraints(minHeight: 32, minWidth: 70),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white60,
            selectedColor: Colors.white,
            fillColor: _p1.withValues(alpha: 0.3),
            children: const [Text('2P'), Text('vs Bot')],
          ),
          const SizedBox(width: 8),
          if (_isAi)
            ToggleButtons(
              isSelected: [
                _botDiff == _SDDifficulty.easy,
                _botDiff == _SDDifficulty.medium,
                _botDiff == _SDDifficulty.hard,
              ],
              onPressed: (i) {
                setState(() {
                  _botDiff = _SDDifficulty.values[i];
                });
                _resetGame();
              },
              constraints: const BoxConstraints(minHeight: 32, minWidth: 50),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white60,
              selectedColor: Colors.white,
              fillColor: _p2.withValues(alpha: 0.3),
              children: const [Text('Easy'), Text('Med'), Text('Hard')],
            ),
          const Spacer(),
          if (_phase == _SDPhase.playing || _phase == _SDPhase.paused)
            IconButton(
              onPressed: () {
                setState(() {
                  _phase = _phase == _SDPhase.paused
                      ? _SDPhase.playing
                      : _SDPhase.paused;
                });
              },
              icon: Icon(
                _phase == _SDPhase.paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: Colors.white70,
              ),
            ),
          IconButton(
            onPressed: () {
              _resetGame();
              setState(() => _phase = _SDPhase.start);
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _SnakeDuelPainter extends CustomPainter {
  _SnakeDuelPainter({
    required this.cell,
    required this.cols,
    required this.rows,
    required this.snake1,
    required this.snake2,
    required this.dir1,
    required this.dir2,
    required this.food,
    required this.p1Color,
    required this.p1HeadColor,
    required this.p2Color,
    required this.p2HeadColor,
    required this.foodColor,
    required this.wallColor,
  });

  final double cell;
  final int cols;
  final int rows;
  final List<Point<int>> snake1;
  final List<Point<int>> snake2;
  final _Dir dir1;
  final _Dir dir2;
  final Point<int> food;
  final Color p1Color;
  final Color p1HeadColor;
  final Color p2Color;
  final Color p2HeadColor;
  final Color foodColor;
  final Color wallColor;

  void _drawSnake(Canvas canvas, List<Point<int>> snake, Color body, _Dir dir, Color headColor) {
    if (snake.isEmpty) return;
    // Body pass: skip head (handled last)
    for (var i = 1; i < snake.length; i++) {
      final seg = snake[i];
      final cx = seg.x * cell + cell / 2;
      final cy = seg.y * cell + cell / 2;
      final scale = max(0.5, 1.0 - (i / max(10, snake.length)));
      final r = (cell / 2 - 1) * scale;
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = body);
      // Connector to prev segment
      final prev = snake[i - 1];
      if ((prev.x - seg.x).abs() + (prev.y - seg.y).abs() == 1) {
        final px = prev.x * cell + cell / 2;
        final py = prev.y * cell + cell / 2;
        canvas.drawLine(
          Offset(px, py),
          Offset(cx, cy),
          Paint()
            ..color = body
            ..strokeWidth = r * 2,
        );
      }
    }
    // Head
    final head = snake.first;
    final hx = head.x * cell + cell / 2;
    final hy = head.y * cell + cell / 2;
    final hr = cell / 2 - 1;
    // Closed mouth ellipse + tongue
    canvas.save();
    canvas.translate(hx, hy);
    var angle = 0.0;
    if (dir == (1, 0)) angle = 0;
    if (dir == (0, -1)) angle = 1.5708; // 90 deg
    if (dir == (-1, 0)) angle = 3.14159; // 180
    if (dir == (0, 1)) angle = 4.7124; // 270
    canvas.rotate(angle);
    final headRect = Rect.fromCenter(
        center: Offset.zero, width: hr * 2.4, height: hr * 2.4);
    canvas.drawOval(headRect, Paint()..color = headColor);
    canvas.drawOval(
      headRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Eyes
    canvas.drawCircle(
        Offset(-hr * 0.2, -hr * 0.55), 3, Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawCircle(
        Offset(-hr * 0.2, hr * 0.55), 3, Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawCircle(
        Offset(-hr * 0.2 + 1, -hr * 0.55 - 1), 1, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(-hr * 0.2 + 1, hr * 0.55 - 1), 1, Paint()..color = Colors.white);
    // Tongue
    canvas.drawLine(
      Offset(hr * 0.7, 0),
      Offset(hr * 1.1, 0),
      Paint()..color = const Color(0xFFFF3232)..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Paint()
      ..color = wallColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4), wall);
    // Food — apple
    final fx = food.x * cell + cell / 2;
    final fy = food.y * cell + cell / 2;
    final r = cell / 2 - 2;
    canvas.drawCircle(Offset(fx, fy), r, Paint()..color = foodColor);
    canvas.drawCircle(
      Offset(fx - r / 3, fy - r / 3),
      r / 3,
      Paint()..color = const Color(0xFFFF6464),
    );
    // Stem
    canvas.drawRect(
      Rect.fromLTWH(fx - 1, fy - r - 3, 2, 4),
      Paint()..color = const Color(0xFF654321),
    );
    // Leaf
    canvas.drawOval(
      Rect.fromLTWH(fx + 1, fy - r - 4, 5, 3),
      Paint()..color = const Color(0xFF228B22),
    );
    // Snakes
    _drawSnake(canvas, snake1, p1Color, dir1, p1HeadColor);
    _drawSnake(canvas, snake2, p2Color, dir2, p2HeadColor);
  }

  @override
  bool shouldRepaint(_SnakeDuelPainter old) =>
      old.snake1 != snake1 ||
      old.snake2 != snake2 ||
      old.food != food ||
      old.dir1 != dir1 ||
      old.dir2 != dir2;
}
