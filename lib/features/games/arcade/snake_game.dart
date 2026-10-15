import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Classic Snake — grid-based, 4-way gesture control, food spawner,
/// collision detection, and progressive speed scaling.
///
/// Controls:
///   * **Swipe** anywhere on the grid to turn 90°.
///   * **D-pad** buttons at the bottom for explicit input.
///   * Tap is ignored — swipes only — so accidental bumps don't die.
class SnakeGame extends MiniGame {
  const SnakeGame({super.key, required super.callbacks});

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends MiniGameState<SnakeGame>
    with SingleTickerProviderStateMixin {
  static const int _cols = 16;
  static const int _rows = 22;

  late List<Point<int>> _snake;
  late Point<int> _food;
  Point<int> _dir = const Point(1, 0);
  Point<int> _nextDir = const Point(1, 0);
  int _score = 0;
  bool _gameOver = false;

  late final Ticker _ticker;
  Duration _step = const Duration(milliseconds: 180);
  DateTime _lastStep = DateTime.now();

  @override
  void initState() {
    super.initState();
    _snake = _initialSnake();
    _food = _spawnFood();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<Point<int>> _initialSnake() => [
        const Point(7, 10),
        const Point(6, 10),
        const Point(5, 10),
      ];

  Point<int> _spawnFood() {
    final rng = Random();
    while (true) {
      final p = Point(rng.nextInt(_cols), rng.nextInt(_rows));
      if (!_snake.contains(p)) return p;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_gameOver) return;
    final now = DateTime.now();
    if (now.difference(_lastStep) < _step) return;
    _lastStep = now;

    // Disallow 180° reversals.
    if (_nextDir.x != -_dir.x || _nextDir.y != -_dir.y) {
      _dir = _nextDir;
    }
    final head = _snake.first;
    final newHead = Point(head.x + _dir.x, head.y + _dir.y);
    if (newHead.x < 0 ||
        newHead.x >= _cols ||
        newHead.y < 0 ||
        newHead.y >= _rows) {
      _die();
      return;
    }
    if (_snake.contains(newHead)) {
      _die();
      return;
    }
    setState(() {
      _snake = [newHead, ..._snake];
      if (newHead == _food) {
        _score += 10;
        _food = _spawnFood();
        // Speed up every 50 points (capped).
        if (_score % 50 == 0) {
          final ms = (_step.inMilliseconds - 8).clamp(60, 200);
          _step = Duration(milliseconds: ms);
        }
        haptic(HapticFeedbackType.light);
        reportScore(_score);
        reportStats('Length ${_snake.length}  •  ${_step.inMilliseconds}ms');
      } else {
        _snake = _snake.sublist(0, _snake.length - 1);
      }
    });
  }

  void _die() {
    if (_gameOver) return;
    setState(() => _gameOver = true);
    haptic(HapticFeedbackType.medium);
    reportScore(_score);
    reportGameOver();
  }

  void _setDir(Point<int> d) {
    if (_gameOver) return;
    if (d.x == -_dir.x && d.y == -_dir.y) return;
    _nextDir = d;
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
                final cell = (c.maxHeight / _rows).clamp(12.0, 28.0);
                final gridW = cell * _cols;
                final gridH = cell * _rows;
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) {
                      // Translate pan into a directional intent.
                      if (d.delta.dx.abs() > d.delta.dy.abs()) {
                        _setDir(Point(d.delta.dx > 0 ? 1 : -1, 0));
                      } else {
                        _setDir(Point(0, d.delta.dy > 0 ? 1 : -1));
                      }
                    },
                    child: SizedBox(
                      width: gridW,
                      height: gridH,
                      child: CustomPaint(
                        painter: _SnakePainter(
                          snake: _snake,
                          food: _food,
                          cell: cell,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _DPad(onChange: _setDir),
        ],
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.onChange});
  final void Function(Point<int>) onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kGamePanel(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.keyboard_arrow_up_rounded, const Point(0, -1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.keyboard_arrow_left_rounded, const Point(-1, 0)),
              const SizedBox(width: 12),
              _btn(Icons.keyboard_arrow_right_rounded, const Point(1, 0)),
            ],
          ),
          _btn(Icons.keyboard_arrow_down_rounded, const Point(0, 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, Point<int> dir) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.white12,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChange(dir),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _SnakePainter extends CustomPainter {
  _SnakePainter({
    required this.snake,
    required this.food,
    required this.cell,
  });

  final List<Point<int>> snake;
  final Point<int> food;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft rounded board background with shadow.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111622), Color(0xFF0B0E14)],
        ).createShader(Offset.zero & size),
    );

    // Grid lines (subtle).
    final gridLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    for (var i = 1; i < 16; i++) {
      canvas.drawLine(
        Offset(i * cell, 0),
        Offset(i * cell, size.height),
        gridLine,
      );
    }
    for (var i = 1; i < 22; i++) {
      canvas.drawLine(
        Offset(0, i * cell),
        Offset(size.width, i * cell),
        gridLine,
      );
    }

    // Food (glossy sphere).
    final foodCenter = Offset(
      food.x * cell + cell / 2,
      food.y * cell + cell / 2,
    );
    canvas.drawCircle(
      foodCenter + const Offset(1, 2),
      cell * 0.35,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawCircle(
      foodCenter,
      cell * 0.35,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 0.95,
          colors: const [
            Color(0xFFFFF3B0),
            Color(0xFFFFB800),
            Color(0xFF8A5A00),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: foodCenter, radius: cell * 0.35)),
    );
    canvas.drawCircle(
      foodCenter + Offset(-cell * 0.08, -cell * 0.10),
      cell * 0.10,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );

    // Snake body — gradient and glossy.
    for (var i = snake.length - 1; i >= 0; i--) {
      final seg = snake[i];
      final alpha = 1.0 - (i / snake.length) * 0.5;
      final base = const Color(0xFF00E887).withValues(alpha: alpha);
      final rect = Rect.fromLTWH(
        seg.x * cell + 1.5,
        seg.y * cell + 1.5,
        cell - 3,
        cell - 3,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      // Drop shadow.
      canvas.drawRRect(
        rr.shift(const Offset(1, 2)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
      // Body with gradient.
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.3) ?? base,
              base,
              Color.lerp(base, Colors.black, 0.3) ?? base,
            ],
          ).createShader(rect),
      );
      // Specular dot on each segment.
      if (i == 0) {
        canvas.drawCircle(
          rect.center + Offset(-cell * 0.10, -cell * 0.10),
          cell * 0.10,
          Paint()..color = Colors.white.withValues(alpha: 0.8),
        );
      }
    }

    // Border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF2A3245)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SnakePainter old) =>
      old.snake != snake || old.food != food || old.cell != cell;
}
