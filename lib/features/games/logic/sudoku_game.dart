import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Sudoku — 9x9 grid with a fixed puzzle. Tap a cell, then pick a
/// number from the keypad. Each row/col/3x3 must contain 1-9 exactly.
class SudokuGame extends MiniGame {
  const SudokuGame({super.key, required super.callbacks});

  @override
  State<SudokuGame> createState() => _State();
}

class _State extends MiniGameState<SudokuGame> {
  late List<List<int>> _puzzle; // 0 = empty
  late List<List<int>> _solution;
  late List<List<bool>> _fixed;
  int? _selected;
  int _score = 0;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    _generate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
    });
  }

  void _generate() {
    // Simple seeded puzzle (medium difficulty) — 40 cells removed
    // from a valid base grid. Hand-tuned for offline playability.
    _solution = _baseSolution();
    _puzzle = List.generate(9, (r) => List.of(_solution[r]));
    _fixed = List.generate(9, (_) => List.filled(9, false));
    final rng = Random();
    var removed = 0;
    while (removed < 40) {
      final r = rng.nextInt(9);
      final c = rng.nextInt(9);
      if (_puzzle[r][c] == 0) continue;
      _puzzle[r][c] = 0;
      _fixed[r][c] = false;
      removed++;
    }
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        _fixed[r][c] = _puzzle[r][c] != 0;
      }
    }
  }

  List<List<int>> _baseSolution() {
    return [
      [5, 3, 4, 6, 7, 8, 9, 1, 2],
      [6, 7, 2, 1, 9, 5, 3, 4, 8],
      [1, 9, 8, 3, 4, 2, 5, 6, 7],
      [8, 5, 9, 7, 6, 1, 4, 2, 3],
      [4, 2, 6, 8, 5, 3, 7, 9, 1],
      [7, 1, 3, 9, 2, 4, 8, 5, 6],
      [9, 6, 1, 5, 3, 7, 2, 8, 4],
      [2, 8, 7, 4, 1, 9, 6, 3, 5],
      [3, 4, 5, 2, 8, 6, 1, 7, 9],
    ];
  }

  void _onTapCell(int r, int c) {
    if (_gameOver) return;
    if (r < 0 || r >= 9 || c < 0 || c >= 9) return;
    if (_fixed[r][c]) return;
    setState(() => _selected = r * 9 + c);
  }

  void _onPickNumber(int n) {
    if (_selected == null) return;
    final r = _selected! ~/ 9;
    final c = _selected! % 9;
    if (r < 0 || r >= 9 || c < 0 || c >= 9) return;
    if (_fixed[r][c]) return;
    setState(() {
      _puzzle[r][c] = n;
      _score += n == _solution[r][c] ? 10 : 0;
    });
    haptic(n == _solution[r][c]
        ? HapticFeedbackType.light
        : HapticFeedbackType.heavy);
    reportScore(_score);
    reportStats('Filled ${_filledCount()}/81');
    _checkWin();
  }

  int _filledCount() {
    var n = 0;
    for (final row in _puzzle) {
      for (final v in row) {
        if (v != 0) n++;
      }
    }
    return n;
  }

  void _checkWin() {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (_puzzle[r][c] != _solution[r][c]) return;
      }
    }
    setState(() => _gameOver = true);
    haptic(HapticFeedbackType.medium);
    reportStats('Solved!');
    reportGameOver();
  }

  void _restart() {
    setState(() {
      _score = 0;
      _gameOver = false;
      _selected = null;
      _generate();
    });
    haptic(HapticFeedbackType.medium);
    reportScore(0);
    reportStats('New puzzle');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final cell = (c.maxWidth / 9).clamp(20.0, 48.0);
                final gridSize = cell * 9;
                // GestureDetector sized to match the CustomPaint exactly
                // so localPosition.dx/dy map 1:1 onto cell coords.
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final r = (d.localPosition.dy / cell).floor();
                      final c2 = (d.localPosition.dx / cell).floor();
                      if (r >= 0 && r < 9 && c2 >= 0 && c2 < 9) {
                        _onTapCell(r, c2);
                      }
                    },
                    child: SizedBox(
                      width: gridSize,
                      height: gridSize,
                      child: CustomPaint(
                        size: Size(gridSize, gridSize),
                        painter: _SudokuPainter(
                          puzzle: _puzzle,
                          fixed: _fixed,
                          selected: _selected,
                          cell: cell,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var n = 1; n <= 9; n++)
                _NumberButton(n: n, onTap: () => _onPickNumber(n)),
              _NumberButton(
                n: 0,
                onTap: () => _onPickNumber(0),
                label: '✕',
              ),
              IconButton(
                onPressed: _restart,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'New puzzle',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberButton extends StatelessWidget {
  const _NumberButton({
    required this.n,
    required this.onTap,
    this.label,
  });
  final int n;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: kGameAccent(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label ?? '$n',
              style: const TextStyle(
                color: Color(0xFF00281A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SudokuPainter extends CustomPainter {
  _SudokuPainter({
    required this.puzzle,
    required this.fixed,
    required this.selected,
    required this.cell,
  });
  final List<List<int>> puzzle;
  final List<List<bool>> fixed;
  final int? selected;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = kGamePanel();
    canvas.drawRect(Offset.zero & size, bg);
    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (var i = 1; i < 9; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height),
          i % 3 == 0 ? thick : line);
      canvas.drawLine(Offset(0, p), Offset(size.width, p),
          i % 3 == 0 ? thick : line);
    }
    if (selected != null) {
      final r = selected! ~/ 9;
      final c = selected! % 9;
      canvas.drawRect(
        Rect.fromLTWH(c * cell, r * cell, cell, cell),
        Paint()..color = kGameAccent().withValues(alpha: 0.25),
      );
    }
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final v = puzzle[r][c];
        if (v == 0) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: '$v',
            style: TextStyle(
              color: fixed[r][c] ? Colors.white : kGameAccent(),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(
          canvas,
          Offset(
            c * cell + cell / 2 - tp.width / 2,
            r * cell + cell / 2 - tp.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SudokuPainter old) =>
      old.puzzle != puzzle || old.selected != selected || old.cell != cell;
}
