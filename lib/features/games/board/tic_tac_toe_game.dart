// Tic Tac Toe — classic minimalist gameplay.
//
//   * Warm orange/peach board background with a soft vignette.
//   * Thick black grid lines (the "+" cross).
//   * Big friendly marks: red X with chunky black outline + blue O ring
//     with matching black outline.
//   * On a win, a solid white line is drawn straight across the
//     winning three cells so the result is unmistakable.
//
// Game logic: player is X, AI is O with full minimax at hard
// difficulty, heuristic on medium, random on easy. Daily-challenge
// mode seeds the AI's openings from today's UTC date.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

class TicTacToeGame extends MiniGame {
  const TicTacToeGame({
    super.key,
    required super.callbacks,
    this.level = 1,
    this.isAiMode = true,
    this.dailyChallenge = false,
  });

  /// Optional level — influences initial AI hint.
  final int level;

  /// Whether the player is facing the AI or playing pass-and-play.
  final bool isAiMode;

  /// When true, the AI's move order / openings are seeded by today's
  /// UTC date so every player faces the same challenge on the same day.
  final bool dailyChallenge;

  @override
  State<TicTacToeGame> createState() => _TicTacToeGameState();
}

enum _TTTDifficulty { easy, medium, hard }

class _TicTacToeGameState extends MiniGameState<TicTacToeGame> {
  final List<String?> _board = List.filled(9, null);
  bool _xTurn = true;
  bool _isAiMode = true;
  late _TTTDifficulty _aiDifficulty;
  int _score = 0;
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;
  bool _gameOver = false;
  String? _winner;

  // Board palette — pulled straight from the original reference design.
  static const Color _boardBg = Color(0xFFFF9470);
  static const Color _boardBgDark = Color(0xFFE07A55);
  static const Color _gridInk = Color(0xFF111827);
  static const Color _xColor = Color(0xFFFF4757);
  static const Color _oColor = Color(0xFF3D8BFD);

  /// Shared seeded RNG so daily-challenge players get the same
  /// openings as everyone else on the same UTC day. Also avoids
  /// re-instantiating `Random()` per AI move.
  late final Random _rng = widget.dailyChallenge
      ? Random(dailySeedFor('tic-tac-toe'))
      : Random();

  @override
  void initState() {
    super.initState();
    _isAiMode = widget.isAiMode;
    _aiDifficulty = widget.level >= 4
        ? _TTTDifficulty.hard
        : (widget.level >= 2 ? _TTTDifficulty.medium : _TTTDifficulty.easy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats(
        _isAiMode
            ? 'W$_wins / L$_losses / D$_draws'
            : 'Pass & play  •  W$_wins / L$_losses / D$_draws',
      );
    });
  }

  // ─── Game flow ────────────────────────────────────────────────────

  void _onTap(int i) {
    if (_gameOver || _board[i] != null) return;
    if (_isAiMode && !_xTurn) return;
    setState(() {
      _board[i] = _xTurn ? 'X' : 'O';
      _xTurn = !_xTurn;
    });
    haptic(HapticFeedbackType.light);
    _checkEnd();
    if (_isAiMode && !_xTurn && !_gameOver) {
      Future.delayed(const Duration(milliseconds: 380), _scheduleAi);
    }
  }

  void _scheduleAi() {
    if (_gameOver) return;
    final move = switch (_aiDifficulty) {
      _TTTDifficulty.easy => _aiRandom(),
      _TTTDifficulty.medium => _aiHeuristic() ?? _aiRandom(),
      _TTTDifficulty.hard => _aiMinimax() ?? _aiRandom(),
    };
    if (move == null) return;
    setState(() {
      _board[move] = 'O';
      _xTurn = true;
    });
    haptic(HapticFeedbackType.selection);
    _checkEnd();
  }

  int? _aiRandom() {
    final empty = <int>[];
    for (var i = 0; i < 9; i++) {
      if (_board[i] == null) empty.add(i);
    }
    if (empty.isEmpty) return null;
    return empty[_rng.nextInt(empty.length)];
  }

  int? _aiHeuristic() {
    final win = _winningMoveFor('O');
    if (win != null) return win;
    final block = _winningMoveFor('X');
    if (block != null) return block;
    return null;
  }

  int? _winningMoveFor(String player) {
    for (var i = 0; i < 9; i++) {
      if (_board[i] != null) continue;
      _board[i] = player;
      final wins = _isWinningLineFor(player);
      _board[i] = null;
      if (wins) return i;
    }
    return null;
  }

  bool _isWinningLineFor(String player) {
    const wins = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final w in wins) {
      if (_board[w[0]] == player &&
          _board[w[1]] == player &&
          _board[w[2]] == player) {
        return true;
      }
    }
    return false;
  }

  int? _aiMinimax() {
    int bestScore = -1000;
    int? bestMove;
    for (var i = 0; i < 9; i++) {
      if (_board[i] == null) {
        _board[i] = 'O';
        final score = _minimax(_board, 0, false);
        _board[i] = null;
        if (score > bestScore) {
          bestScore = score;
          bestMove = i;
        }
      }
    }
    return bestMove;
  }

  int _minimax(List<String?> b, int depth, bool isMax) {
    final winner = _winnerOn(b);
    if (winner == 'O') return 10 - depth;
    if (winner == 'X') return depth - 10;
    final empty = b.where((c) => c == null).length;
    if (empty == 0) return 0;
    if (isMax) {
      int best = -1000;
      for (var i = 0; i < 9; i++) {
        if (b[i] == null) {
          b[i] = 'O';
          best = max(best, _minimax(b, depth + 1, false));
          b[i] = null;
        }
      }
      return best;
    } else {
      int best = 1000;
      for (var i = 0; i < 9; i++) {
        if (b[i] == null) {
          b[i] = 'X';
          best = min(best, _minimax(b, depth + 1, true));
          b[i] = null;
        }
      }
      return best;
    }
  }

  String? _winnerOn(List<String?> b) {
    const wins = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final w in wins) {
      final a = b[w[0]];
      if (a != null && a == b[w[1]] && a == b[w[2]]) return a;
    }
    return null;
  }

  void _checkEnd() {
    final w = _winnerOn(_board);
    if (w != null) {
      setState(() {
        _winner = w;
        _gameOver = true;
        final aiWon = w == 'O' && _isAiMode;
        final playerWon = w == 'X';
        if (playerWon) {
          _score += 100;
          _wins++;
        } else if (aiWon) {
          _losses++;
        } else {
          _score += 100;
          _wins++;
        }
      });
      haptic(HapticFeedbackType.medium);
      reportScore(_score);
      reportStats('W$_wins / L$_losses / D$_draws');
      reportGameOver();
      return;
    }
    if (!_board.contains(null)) {
      setState(() {
        _gameOver = true;
        _score += 25;
        _draws++;
      });
      haptic(HapticFeedbackType.selection);
      reportScore(_score);
      reportStats('W$_wins / L$_losses / D$_draws');
      reportGameOver();
    }
  }

  List<int>? _winningLine() {
    if (_winner == null) return null;
    const wins = [
      [0, 1, 2],
      [3, 4, 5],
      [6, 7, 8],
      [0, 3, 6],
      [1, 4, 7],
      [2, 5, 8],
      [0, 4, 8],
      [2, 4, 6],
    ];
    for (final w in wins) {
      final a = _board[w[0]];
      if (a != null && a == _board[w[1]] && a == _board[w[2]]) return w;
    }
    return null;
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _boardBg,
      child: SafeArea(
        child: Stack(
          children: [
            // Vignette background.
            Positioned.fill(
              child: CustomPaint(
                painter: _BackgroundPainter(),
              ),
            ),
            // End-of-game card removed — host GameContainerScreen provides it.
            // The board.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 24),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = c.maxWidth < c.maxHeight
                        ? c.maxWidth
                        : c.maxHeight;
                    final board = side.clamp(220.0, 520.0);
                    return Center(
                      child: SizedBox(
                        width: board,
                        height: board,
                        child: _BoardArea(
                          board: _board,
                          highlight: _winningLine(),
                          cellSize: board / 3,
                          boardBg: _boardBg,
                          boardBgDark: _boardBgDark,
                          gridInk: _gridInk,
                          xColor: _xColor,
                          oColor: _oColor,
                          onTap: _onTap,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Board area — paints the slate-blue background, the cross grid, the
// marks, and the winning-line highlight straight across the
// successful three cells.
// ────────────────────────────────────────────────────────────────────

class _BoardArea extends StatelessWidget {
  const _BoardArea({
    required this.board,
    required this.highlight,
    required this.cellSize,
    required this.boardBg,
    required this.boardBgDark,
    required this.gridInk,
    required this.xColor,
    required this.oColor,
    required this.onTap,
  });

  final List<String?> board;
  final List<int>? highlight;
  final double cellSize;
  final Color boardBg;
  final Color boardBgDark;
  final Color gridInk;
  final Color xColor;
  final Color oColor;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final size = cellSize * 3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _BoardPainter(
                board: board,
                highlight: highlight,
                boardBg: boardBg,
                boardBgDark: boardBgDark,
                gridInk: gridInk,
                xColor: xColor,
                oColor: oColor,
                cellSize: cellSize,
              ),
            ),
          ),
          // Tap targets.
          Padding(
            padding: EdgeInsets.zero,
            child: GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < 9; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: const SizedBox.expand(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.highlight,
    required this.boardBg,
    required this.boardBgDark,
    required this.gridInk,
    required this.xColor,
    required this.oColor,
    required this.cellSize,
  });

  final List<String?> board;
  final List<int>? highlight;
  final Color boardBg;
  final Color boardBgDark;
  final Color gridInk;
  final Color xColor;
  final Color oColor;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = cellSize;
    final grid = cell * 0.16; // very thick lines

    // ── Board background ─────────────────────────────────────────
    final bgRect = Offset.zero & size;
    final bgRRect = RRect.fromRectAndRadius(bgRect, Radius.circular(cell * 0.18));

    // Drop shadow.
    canvas.drawRRect(
      bgRRect.shift(Offset(0, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Top-down gradient for depth.
    canvas.drawRRect(
      bgRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [boardBg, boardBgDark],
        ).createShader(bgRect),
    );

    // Vignette.
    canvas.save();
    canvas.clipRRect(bgRRect);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.18),
          ],
          stops: const [0.6, 1.0],
        ).createShader(bgRect),
    );
    canvas.restore();

    // ── Marks (X / O) — drawn before the grid so the grid lines
    // sit crisply on top.
    for (var i = 0; i < 9; i++) {
      final r = (i / 3).floor();
      final c = i % 3;
      final cx = c * cell + cell / 2;
      final cy = r * cell + cell / 2;
      final mark = board[i];
      if (mark == null) continue;
      canvas.save();
      canvas.translate(cx, cy);
      if (mark == 'X') {
        _drawX(canvas, cell * 0.32);
      } else {
        _drawO(canvas, cell * 0.32);
      }
      canvas.restore();
    }

    // ── Winning line — solid white straight across the three
    // matching cells, exactly like the reference design. ──
    if (highlight != null && highlight!.length == 3) {
      final c1 = _center(highlight![0], cell, size);
      final c3 = _center(highlight![2], cell, size);
      // Dark outline so the white reads cleanly on the colored
      // marks (red X / blue O) underneath.
      final outline = Paint()
        ..color = const Color(0xFF111827)
        ..strokeCap = StrokeCap.square
        ..strokeWidth = grid * 1.2;
      canvas.drawLine(c1, c3, outline);
      final line = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = grid * 0.7
        ..strokeCap = StrokeCap.square;
      canvas.drawLine(c1, c3, line);
    }

    // ── Thick black cross grid ──────────────────────────────────
    final gridPaint = Paint()
      ..color = gridInk
      ..strokeWidth = grid
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(cell, 0), Offset(cell, size.height), gridPaint);
    canvas.drawLine(Offset(cell * 2, 0), Offset(cell * 2, size.height), gridPaint);
    canvas.drawLine(Offset(0, cell), Offset(size.width, cell), gridPaint);
    canvas.drawLine(Offset(0, cell * 2), Offset(size.width, cell * 2), gridPaint);

    // Soft inner highlight on top of the grid for that hand-drawn feel.
    final hi = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = grid * 0.22
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(cell - grid * 0.1, 0), Offset(cell - grid * 0.1, size.height), hi);
    canvas.drawLine(Offset(cell * 2 - grid * 0.1, 0), Offset(cell * 2 - grid * 0.1, size.height), hi);
    canvas.drawLine(Offset(0, cell - grid * 0.1), Offset(size.width, cell - grid * 0.1), hi);
    canvas.drawLine(Offset(0, cell * 2 - grid * 0.1), Offset(size.width, cell * 2 - grid * 0.1), hi);
  }

  Offset _center(int i, double cell, Size size) {
    final r = (i / 3).floor();
    final c = i % 3;
    return Offset(c * cell + cell / 2, r * cell + cell / 2);
  }

  void _drawX(Canvas canvas, double r) {
    // Thick black outline.
    final outline = Paint()
      ..color = gridInk
      ..strokeWidth = r * 1.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r, -r), Offset(r, r), outline);
    canvas.drawLine(Offset(r, -r), Offset(-r, r), outline);

    // Filled red strokes.
    final fill = Paint()
      ..color = xColor
      ..strokeWidth = r * 0.62
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r, -r), Offset(r, r), fill);
    canvas.drawLine(Offset(r, -r), Offset(-r, r), fill);

    // Specular highlight.
    final spec = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-r * 0.95, -r * 0.45),
      Offset(r * 0.15, r * 0.65),
      spec,
    );
  }

  void _drawO(Canvas canvas, double r) {
    final outline = Paint()
      ..color = gridInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 1.05;
    canvas.drawCircle(Offset.zero, r, outline);

    final ring = Paint()
      ..color = oColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.62;
    canvas.drawCircle(Offset.zero, r, ring);

    final spec = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16;
    final arc = Path()
      ..addArc(
        Rect.fromCircle(center: Offset.zero, radius: r),
        -2.6,
        1.4,
      );
    canvas.drawPath(arc, spec);
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.board != board ||
      old.highlight != highlight ||
      old.cellSize != cellSize;
}

// ────────────────────────────────────────────────────────────────────
// Background painter — soft vignette.
// ────────────────────────────────────────────────────────────────────

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Color(0xFFFFA78F),
          Color(0xFFE07A55),
        ],
        stops: [0.0, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) => false;
}
