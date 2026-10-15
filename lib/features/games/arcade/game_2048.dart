import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// 2048 — 4x4 sliding tile matrix with swipe mechanics and animated
/// merges. Win when a 2048 tile is on the board; lose when the grid
/// fills up with no possible merges.
class Game2048Widget extends MiniGame {
  const Game2048Widget({super.key, required super.callbacks});

  @override
  State<Game2048Widget> createState() => _Game2048State();
}

class _Game2048State extends MiniGameState<Game2048Widget>
    with SingleTickerProviderStateMixin {
  static const int _size = 4;
  late List<List<int>> _grid;
  int _score = 0;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    _grid = List.generate(_size, (_) => List.filled(_size, 0));
    _spawn();
    _spawn();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
    });
  }

  void _spawn() {
    final rng = Random();
    final empty = <Point<int>>[];
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) empty.add(Point(c, r));
      }
    }
    if (empty.isEmpty) return;
    final p = empty[rng.nextInt(empty.length)];
    _grid[p.y][p.x] = rng.nextInt(10) < 9 ? 2 : 4;
  }

  bool _slide(int dx, int dy) {
    if (_gameOver) return false;
    // Build a new grid by walking each row/col in the direction
    // (dx, dy), merging equal adjacent cells.
    bool moved = false;
    final newGrid = List.generate(_size, (_) => List.filled(_size, 0));
    int gained = 0;

    for (var i = 0; i < _size; i++) {
      // Indices in the direction of motion (start = farthest cell).
      final indices = <Point<int>>[];
      if (dx != 0) {
        for (var j = 0; j < _size; j++) {
          indices.add(Point(j, i));
        }
        if (dx < 0) indices.sort((a, b) => a.x.compareTo(b.x));
        if (dx > 0) indices.sort((a, b) => b.x.compareTo(a.x));
      } else {
        for (var j = 0; j < _size; j++) {
          indices.add(Point(i, j));
        }
        if (dy > 0) indices.sort((a, b) => b.y.compareTo(a.y));
        if (dy < 0) indices.sort((a, b) => a.y.compareTo(b.y));
      }

      int writeR = dy == -1 ? 0 : dy == 1 ? _size - 1 : i;
      int writeC = dx == -1 ? 0 : dx == 1 ? _size - 1 : i;
      int? prevValue;
      for (final p in indices) {
        final v = _grid[p.y][p.x];
        if (v == 0) continue;
        if (prevValue == null) {
          newGrid[writeR][writeC] = v;
          prevValue = v;
        } else if (prevValue == v) {
          newGrid[writeR][writeC] = v * 2;
          gained += v * 2;
          prevValue = null;
          // Advance write cursor.
          if (dx == 1) writeC--;
          if (dx == -1) writeC++;
          if (dy == 1) writeR--;
          if (dy == -1) writeR++;
        } else {
          // Place prev and start new.
          if (dx == 1) writeC--;
          if (dx == -1) writeC++;
          if (dy == 1) writeR--;
          if (dy == -1) writeR++;
          newGrid[writeR][writeC] = v;
          prevValue = v;
        }
      }
    }
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (newGrid[r][c] != _grid[r][c]) {
          moved = true;
        }
      }
    }
    if (!moved) return false;
    setState(() {
      _grid = newGrid;
      _score += gained;
    });
    haptic(HapticFeedbackType.selection);
    _spawn();
    reportScore(_score);
    reportStats('Best ${_bestTile()}');
    if (_isFull()) {
      setState(() => _gameOver = true);
      haptic(HapticFeedbackType.medium);
      reportGameOver();
    }
    return true;
  }

  int _bestTile() {
    var best = 0;
    for (final row in _grid) {
      for (final v in row) {
        if (v > best) best = v;
      }
    }
    return best;
  }

  bool _isFull() {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) return false;
        if (c + 1 < _size && _grid[r][c] == _grid[r][c + 1]) return false;
        if (r + 1 < _size && _grid[r][c] == _grid[r + 1][c]) return false;
      }
    }
    return true;
  }

  static Color _tileColor(int v) {
    switch (v) {
      case 0:
        return const Color(0xFF1A2233);
      case 2:
        return const Color(0xFF243047);
      case 4:
        return const Color(0xFF2D3A56);
      case 8:
        return const Color(0xFF38BDF8);
      case 16:
        return const Color(0xFF22C55E);
      case 32:
        return const Color(0xFFFFD166);
      case 64:
        return const Color(0xFFF97316);
      case 128:
        return const Color(0xFFA855F7);
      case 256:
        return const Color(0xFFEC4899);
      case 512:
        return const Color(0xFFEF4444);
      case 1024:
        return const Color(0xFFFBBF24);
      default:
        return const Color(0xFF00E887);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cell = ((c.maxWidth - 24) / _size).clamp(40.0, 100.0);
                final size = cell * _size + (_size - 1) * 8.0;
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) {
                      if (d.delta.dx.abs() > d.delta.dy.abs()) {
                        _slide(d.delta.dx > 0 ? 1 : -1, 0);
                      } else {
                        _slide(0, d.delta.dy > 0 ? 1 : -1);
                      }
                    },
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: CustomPaint(
                        painter: _Grid2048Painter(
                          grid: _grid,
                          cell: cell,
                          gap: 8,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid2048Painter extends CustomPainter {
  _Grid2048Painter({
    required this.grid,
    required this.cell,
    required this.gap,
  });
  final List<List<int>> grid;
  final double cell;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = kGamePanel();
    canvas.drawRect(Offset.zero & size, bg);
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid.length; c++) {
        final v = grid[r][c];
        final x = c * (cell + gap);
        final y = r * (cell + gap);
        final rect = Rect.fromLTWH(x + 4, y + 4, cell - 8, cell - 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          Paint()..color = _Game2048State._tileColor(v).withValues(alpha: 0.85),
        );
        if (v != 0) {
          final tp = TextPainter(
            text: TextSpan(
              text: '$v',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: v >= 1000 ? 18 : 24,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          tp.paint(
            canvas,
            Offset(
              x + cell / 2 - tp.width / 2,
              y + cell / 2 - tp.height / 2,
            ),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Grid2048Painter old) =>
      old.grid != grid || old.cell != cell;
}
