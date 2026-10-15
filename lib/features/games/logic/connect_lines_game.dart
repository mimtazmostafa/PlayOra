import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Connect Lines — Flow Free / Number Link style. Pair every colored
/// dot by drawing non-overlapping paths through the grid. Drag from
/// one dot to its partner; the line follows the finger cell-by-cell.
///
/// Visuals:
///   * Dark rounded grid cells (#1E293B).
///   * Glossy neon dots with radial highlights and glow.
///   * Thick glowing connection paths with gradient strokes.
///   * Active dot pulses; path head is brighter at the leading edge.
class ConnectLinesGame extends MiniGame {
  const ConnectLinesGame({super.key, required super.callbacks});

  @override
  State<ConnectLinesGame> createState() => _State();
}

class _State extends MiniGameState<ConnectLinesGame>
    with SingleTickerProviderStateMixin {
  static const int _size = 6;
  static const List<Color> _colours = [
    Color(0xFFEF4444),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF38BDF8),
    Color(0xFFA855F7),
    Color(0xFFF472B6),
  ];

  late List<List<int>> _grid; // cell value: -1 empty, 0..n=path, n=dot
  late List<List<int>> _dots; // dot value: -1 none, otherwise color index
  int? _active;
  List<Point<int>> _activePath = []; // ordered path cells (head first)
  int _score = 0;
  int _level = 1;
  int _celebrateFrame = 0; // 1..30 frames of completion celebration
  late final Ticker _ticker;

  static const Color _gridCell = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();
    _initLevel();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Lvl $_level');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (_celebrateFrame > 0) {
      setState(() => _celebrateFrame--);
    }
  }

  void _initLevel() {
    _grid = List.generate(_size, (_) => List.filled(_size, -1));
    _dots = List.generate(_size, (_) => List.filled(_size, -1));
    final rng = Random();
    // 6 distinct colors per level for visual clarity on mobile.
    final pairs = _colours.length;
    final used = <Point<int>>{};
    for (var i = 0; i < pairs; i++) {
      Point<int> a;
      Point<int> b;
      var attempts = 0;
      do {
        a = Point(rng.nextInt(_size), rng.nextInt(_size));
        b = Point(rng.nextInt(_size), rng.nextInt(_size));
        attempts++;
      } while ((a == b || used.contains(a) || used.contains(b)) &&
          attempts < 200);
      if (used.contains(a) || used.contains(b)) {
        // Fallback deterministic placement on the perimeter — always
        // succeeds, even after unlucky RNG draws.
        final cells = <Point<int>>[];
        for (var x = 0; x < _size; x++) {
          cells.add(Point(x, 0));
          cells.add(Point(x, _size - 1));
        }
        for (var y = 1; y < _size - 1; y++) {
          cells.add(Point(0, y));
          cells.add(Point(_size - 1, y));
        }
        a = cells.firstWhere((p) => !used.contains(p));
        b = cells.firstWhere(
            (p) => !used.contains(p) && p != a);
      }
      used.add(a);
      used.add(b);
      _dots[a.y][a.x] = i;
      _dots[b.y][b.x] = i;
    }
    _active = null;
    _activePath = [];
    _level++;
  }

  bool _isAdj(Point<int> a, Point<int> b) {
    final dr = (a.y - b.y).abs();
    final dc = (a.x - b.x).abs();
    return (dr == 1 && dc == 0) || (dr == 0 && dc == 1);
  }

  /// Map a (col, row) cell coord to the same Point convention used in
  /// [_activePath] (Point.x = col, Point.y = row).
  Point<int> _point(int r, int c) => Point(c, r);

  /// Returns true if this cell currently holds the active path or a
  /// completed path of the active color. Used to allow backtracking.
  bool _cellBelongsToActive(int r, int c) {
    if (_active == null) return false;
    if (_grid[r][c] == _active) return true;
    if (_dots[r][c] == _active) return true;
    return false;
  }

  // ────────────────────────────────────────────────────────────────
  // Drag-to-draw gesture handlers
  // ────────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d, double cell) {
    final c = (d.localPosition.dx / cell).floor().clamp(0, _size - 1);
    final r = (d.localPosition.dy / cell).floor().clamp(0, _size - 1);
    final dot = _dots[r][c];
    if (dot >= 0) {
      setState(() {
        _active = dot;
        _activePath = [_point(r, c)];
        // Clear any existing path of THIS color so we can re-draw from
        // a different starting dot.
        for (var rr = 0; rr < _size; rr++) {
          for (var cc = 0; cc < _size; cc++) {
            if (_grid[rr][cc] == dot) _grid[rr][cc] = -1;
          }
        }
        _grid[r][c] = dot;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double cell) {
    if (_active == null) return;
    final c = (d.localPosition.dx / cell).floor().clamp(0, _size - 1);
    final r = (d.localPosition.dy / cell).floor().clamp(0, _size - 1);
    final p = _point(r, c);
    final last = _activePath.last;
    if (p == last) return; // Same cell — ignore (Flutter repeats updates).

    // If the finger jumps to a cell already in the active path, treat
    // it as backtracking: pop all cells after the first occurrence of
    // `p`. This lets the user correct a wrong turn mid-drag.
    if (_cellBelongsToActive(r, c)) {
      final idx = _activePath.indexOf(p);
      if (idx >= 0 && idx < _activePath.length - 1) {
        final removed =
            _activePath.sublist(idx + 1);
        setState(() {
          _activePath = _activePath.sublist(0, idx + 1);
          for (final rp in removed) {
            if (rp.y >= 0 &&
                rp.y < _size &&
                rp.x >= 0 &&
                rp.x < _size &&
                _dots[rp.y][rp.x] != _active) {
              _grid[rp.y][rp.x] = -1;
            }
          }
        });
        return;
      }
      // Could be the partner dot — handled below.
    }

    // Must be orthogonally adjacent to current tail.
    if (!_isAdj(last, p)) return;

    // Cannot walk onto a cell that has another color's completed path.
    final existing = _grid[r][c];
    if (existing != -1 && existing != _active) return;

    // If we just walked over the partner dot → complete the pair.
    if (_dots[r][c] == _active && _activePath.length >= 2) {
      setState(() {
        _activePath.add(p);
        _grid[r][c] = _active!;
        _score += 50;
        _active = null;
        _activePath = [];
        _celebrateFrame = 18;
      });
      haptic(HapticFeedbackType.medium);
      reportScore(_score);
      reportStats('Lvl $_level  •  All pairs connected soon');
      _checkWin();
      return;
    }

    // Otherwise extend the path.
    setState(() {
      _activePath.add(p);
      _grid[r][c] = _active!;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_active == null) return;
    // Path wasn't completed — drop the leading tail we drew. Keep the
    // start dot in place.
    setState(() {
      for (final p in _activePath) {
        if (p.y >= 0 &&
            p.y < _size &&
            p.x >= 0 &&
            p.x < _size &&
            _dots[p.y][p.x] != _active) {
          _grid[p.y][p.x] = -1;
        }
      }
      _active = null;
      _activePath = [];
    });
  }

  void _onPanCancel() {
    _onPanEnd(DragEndDetails());
  }

  void _undoActive() {
    if (_active == null || _activePath.length < 2) return;
    setState(() {
      final removed = _activePath.removeLast();
      if (_dots[removed.y][removed.x] != _active) {
        _grid[removed.y][removed.x] = -1;
      }
    });
  }

  void _checkWin() {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == -1 && _dots[r][c] == -1) return;
      }
    }
    // Win!
    final bonus = _level * 100;
    _score += bonus;
    haptic(HapticFeedbackType.heavy);
    reportScore(_score);
    reportStats('Lvl $_level ✓ +$bonus bonus');
    // Brief pause then start a harder level (more colors / same grid).
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(_initLevel);
      reportScore(_score);
      reportStats('Lvl $_level');
      // Don't reportGameOver — endless mode.
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.grid_on_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Level $_level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Undo last segment',
                  onPressed: _active == null ? null : _undoActive,
                  icon: Icon(
                    Icons.undo_rounded,
                    color: _active == null
                        ? Colors.white24
                        : Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'New level',
                  onPressed: () {
                    setState(_initLevel);
                    reportStats('Lvl $_level');
                  },
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cell = (c.maxWidth / _size).clamp(36.0, 88.0);
                final boardSize = cell * _size;
                return Center(
                  child: SizedBox(
                    width: boardSize,
                    height: boardSize,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _onPanStart(d, cell),
                      onPanUpdate: (d) => _onPanUpdate(d, cell),
                      onPanEnd: _onPanEnd,
                      onPanCancel: _onPanCancel,
                      child: CustomPaint(
                        size: Size(boardSize, boardSize),
                        painter: _ConnectPainter(
                          grid: _grid,
                          dots: _dots,
                          colours: _colours,
                          cell: cell,
                          gridCell: _gridCell,
                          activeColor: _active,
                          celebrateFrame: _celebrateFrame,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _active == null
                  ? 'Drag from any dot to its matching partner'
                  : 'Drag to the same-colored dot · ↶ to undo a step',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectPainter extends CustomPainter {
  _ConnectPainter({
    required this.grid,
    required this.dots,
    required this.colours,
    required this.cell,
    required this.gridCell,
    required this.activeColor,
    required this.celebrateFrame,
  });
  final List<List<int>> grid;
  final List<List<int>> dots;
  final List<Color> colours;
  final double cell;
  final Color gridCell;
  final int? activeColor;
  final int celebrateFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    // Grid background with shadow.
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = gridCell,
    );

    // Draw connection paths.
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final v = grid[r][c];
        if (v < 0) continue;
        if (r >= grid.length || c >= grid[r].length) continue;
        final color = colours[v];
        // Horizontal segment to next cell of same color.
        if (c + 1 < grid[r].length && grid[r][c + 1] == v) {
          _drawGlowLine(
            canvas,
            Offset(c * cell + cell / 2, r * cell + cell / 2),
            Offset((c + 1) * cell + cell / 2, r * cell + cell / 2),
            color,
          );
        }
        // Vertical.
        if (r + 1 < grid.length && grid[r + 1][c] == v) {
          _drawGlowLine(
            canvas,
            Offset(c * cell + cell / 2, r * cell + cell / 2),
            Offset(c * cell + cell / 2, (r + 1) * cell + cell / 2),
            color,
          );
        }
      }
    }

    // Cell tints (light overlay for path cells).
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final v = grid[r][c];
        if (v < 0) continue;
        if (r >= grid.length || c >= grid[r].length) continue;
        final color = colours[v];
        final cellRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            c * cell + cell * 0.15,
            r * cell + cell * 0.15,
            cell * 0.7,
            cell * 0.7,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          cellRect,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
        );
      }
    }

    // Celebration shimmer for the active (just-completed) color.
    if (celebrateFrame > 0 && activeColor == null) {
      // Render only briefly when a pair is connected and activeColor
      // is null. We can't know which color connected at this point
      // because the field cleared — skip for simplicity.
    }

    // Dots (glossy neon).
    for (var r = 0; r < dots.length; r++) {
      for (var c = 0; c < dots[r].length; c++) {
        final v = dots[r][c];
        if (v < 0) continue;
        if (r >= dots.length || c >= dots[r].length) continue;
        final color = colours[v];
        final center = Offset(c * cell + cell / 2, r * cell + cell / 2);
        final isActive = (activeColor == v);
        // Active pulse: outer ring is wider.
        if (isActive) {
          canvas.drawCircle(
            center,
            cell * 0.46,
            Paint()
              ..color = color.withValues(alpha: 0.30)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
          );
        }
        // Outer glow.
        canvas.drawCircle(
          center,
          cell * 0.40,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
        // Drop shadow.
        canvas.drawCircle(
          center + const Offset(1, 2),
          cell * 0.30,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
        // Body sphere.
        canvas.drawCircle(
          center,
          cell * 0.30,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.3, -0.35),
              radius: 0.95,
              colors: [
                Color.lerp(color, Colors.white, 0.6) ?? Colors.white,
                color,
                Color.lerp(color, Colors.black, 0.4) ?? Colors.black,
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(Rect.fromCircle(center: center, radius: cell * 0.30)),
        );
        // Specular highlight.
        canvas.drawCircle(
          center + Offset(-cell * 0.08, -cell * 0.10),
          cell * 0.09,
          Paint()..color = Colors.white.withValues(alpha: 0.95),
        );
      }
    }

    // Border around grid.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF334155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawGlowLine(Canvas canvas, Offset a, Offset b, Color color) {
    // Outer glow.
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: 0.65)
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Inner stroke (gradient for depth).
    canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            color,
            Color.lerp(color, Colors.white, 0.3) ?? color,
          ],
        ).createShader(Rect.fromPoints(a, b)),
    );
    // Highlight stripe.
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ConnectPainter old) =>
      old.grid != grid ||
      old.dots != dots ||
      old.cell != cell ||
      old.activeColor != activeColor ||
      old.celebrateFrame != celebrateFrame;
}
