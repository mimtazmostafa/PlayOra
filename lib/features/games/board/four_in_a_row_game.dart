import 'dart:math';

import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../mini_game.dart';
import '../widgets/game_flow_overlays.dart';

/// Connect Four — single-screen gravity-drop disc game in the
/// "Pool / Backgammon / Maze Escape" mini-game family.
///
/// Match the reference: blue Connect Four frame with six columns of
/// seven rows, red discs (You) vs yellow discs (Bot). Tap a column to
/// drop a disc; the disc falls to the lowest empty row. Get 4 in a
/// row — horizontally, vertically or diagonally — to win.
///
/// Win condition: land 4 of your own 4-in-a-row lines within the
/// shown move budget.
///
/// Phases: `start → play → win → trophy`.
class FourInARowGame extends MiniGame {
  const FourInARowGame({
    super.key,
    required super.callbacks,
    this.level = 1,
  });

  /// 1 = easy, 2 = medium, 3+ = hard bot. Kept for back-compat with
  /// the dispatcher; the rewrite always uses a depth-2 heuristic.
  final int level;

  @override
  State<FourInARowGame> createState() => _FourInARowGameState();
}

enum _C4Phase { start, play, win, trophy }

enum _C4Cell { empty, you, bot }

class _FourInARowGameState extends MiniGameState<FourInARowGame> {
  static const int _cols = 7;
  static const int _rows = 6;

  /// How many 4-in-a-rows you need to land to win.
  static const int _youTarget = 4;

  /// Move budget shown on the start screen.
  int get _moveBudget => _cols * _rows ~/ 2;

  late List<List<_C4Cell>> _grid;
  _C4Phase _phase = _C4Phase.start;
  int _yourCount = 0;
  int _botCount = 0;
  int _movesLeft = 0;
  int _score = 0;
  bool _isYouTurn = true;
  final Random _rng = Random();

  /// Column currently being hovered. Null when not hovering. Drives
  /// the floating preview disc.
  int? _hoverCol;

  /// Drop animation in progress.
  int? _dropCol;
  double _dropT = 0;

  @override
  void initState() {
    super.initState();
    _resetBoard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('You 0/$_youTarget  •  Moves Left $_movesLeft');
    });
  }

  void _resetBoard() {
    _grid = List.generate(
      _rows,
      (_) => List.filled(_cols, _C4Cell.empty),
    );
    _yourCount = 0;
    _botCount = 0;
    _movesLeft = _moveBudget;
    _isYouTurn = true;
    _hoverCol = null;
    _dropCol = null;
    _dropT = 0;
  }

  void _refreshHud() {
    reportScore(_score);
    reportStats('You $_yourCount/$_youTarget  •  Moves Left $_movesLeft');
  }

  void _onPlay() {
    setState(() {
      _phase = _C4Phase.play;
      _score = 0;
      _resetBoard();
    });
    _refreshHud();
  }

  void _onPlayAgain() {
    setState(() {
      _phase = _C4Phase.start;
      _score = 0;
      _resetBoard();
    });
    _refreshHud();
  }

  // ── Game logic ───────────────────────────────────────────────────

  /// Returns the lowest empty row in [col], or -1 if full.
  int _lowestEmpty(int col) {
    for (var r = _rows - 1; r >= 0; r--) {
      if (_grid[r][col] == _C4Cell.empty) return r;
    }
    return -1;
  }

  bool _isBoardFull() {
    for (var c = 0; c < _cols; c++) {
      if (_grid[0][c] == _C4Cell.empty) return false;
    }
    return true;
  }

  /// Counts 4-in-a-row threats for [who] in [grid].
  int _countLines(_C4Cell who, List<List<_C4Cell>> grid) {
    var count = 0;
    // Horizontal
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c <= _cols - 4; c++) {
        if (grid[r][c] == who &&
            grid[r][c + 1] == who &&
            grid[r][c + 2] == who &&
            grid[r][c + 3] == who) {
          count++;
        }
      }
    }
    // Vertical
    for (var c = 0; c < _cols; c++) {
      for (var r = 0; r <= _rows - 4; r++) {
        if (grid[r][c] == who &&
            grid[r + 1][c] == who &&
            grid[r + 2][c] == who &&
            grid[r + 3][c] == who) {
          count++;
        }
      }
    }
    // Diagonal \
    for (var r = 0; r <= _rows - 4; r++) {
      for (var c = 0; c <= _cols - 4; c++) {
        if (grid[r][c] == who &&
            grid[r + 1][c + 1] == who &&
            grid[r + 2][c + 2] == who &&
            grid[r + 3][c + 3] == who) {
          count++;
        }
      }
    }
    // Diagonal /
    for (var r = 3; r < _rows; r++) {
      for (var c = 0; c <= _cols - 4; c++) {
        if (grid[r][c] == who &&
            grid[r - 1][c + 1] == who &&
            grid[r - 2][c + 2] == who &&
            grid[r - 3][c + 3] == who) {
          count++;
        }
      }
    }
    return count;
  }

  /// Bot move: pick the column that maximises its own line count
  /// while blocking the player's. Centre columns preferred.
  int _botChooseColumn() {
    var bestCol = _cols ~/ 2;
    var bestScore = -100000;
    for (var c = 0; c < _cols; c++) {
      final r = _lowestEmpty(c);
      if (r < 0) continue;
      _grid[r][c] = _C4Cell.bot;
      final botLines = _countLines(_C4Cell.bot, _grid);
      _grid[r][c] = _C4Cell.you;
      final yourThreat = _countLines(_C4Cell.you, _grid);
      _grid[r][c] = _C4Cell.empty;
      // Offence first, defence a hair above, slight centre bias.
      final score =
          botLines * 100 - yourThreat * 110 + (3 - (c - _cols ~/ 2).abs()) * 2;
      if (score > bestScore) {
        bestScore = score;
        bestCol = c;
      }
    }
    // Small jitter so it's not perfectly deterministic.
    if (_rng.nextDouble() < 0.15) {
      final alt = (bestCol + (_rng.nextBool() ? 1 : -1)).clamp(0, _cols - 1);
      if (_lowestEmpty(alt) >= 0) bestCol = alt;
    }
    return bestCol;
  }

  void _onColumnTap(int col) {
    if (_phase != _C4Phase.play) return;
    if (!_isYouTurn) return;
    if (_dropCol != null) return;
    final r = _lowestEmpty(col);
    if (r < 0) return;
    setState(() {
      _grid[r][col] = _C4Cell.you;
      _dropCol = col;
      _dropT = 0;
      _isYouTurn = false;
    });
    haptic(HapticFeedbackType.light);
    _animateDrop(col, r);
  }

  Future<void> _animateDrop(int col, int targetRow) async {
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      setState(() {
        _dropT = (i + 1) / 12;
      });
    }
    setState(() {
      _dropCol = null;
    });
    _yourCount = _countLines(_C4Cell.you, _grid);
    _movesLeft--;
    _score = _yourCount * 100 + (_movesLeft * 5);
    _refreshHud();

    if (_yourCount >= _youTarget) {
      haptic(HapticFeedbackType.heavy);
      reportGameOver();
      setState(() {
        _phase = _C4Phase.win;
      });
      return;
    }
    if (_isBoardFull() || _movesLeft <= 0) {
      _score = _yourCount * 100;
      haptic(HapticFeedbackType.selection);
      reportGameOver();
      setState(() {
        _phase = _C4Phase.trophy;
      });
      return;
    }
    // Bot's turn.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_phase != _C4Phase.play) return;
      final col = _botChooseColumn();
      final r = _lowestEmpty(col);
      if (r < 0) return;
      setState(() {
        _grid[r][col] = _C4Cell.bot;
        _dropCol = col;
        _dropT = 0;
      });
      _animateBotDrop(col, r);
    });
  }

  Future<void> _animateBotDrop(int col, int targetRow) async {
    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      setState(() {
        _dropT = (i + 1) / 12;
      });
    }
    setState(() {
      _dropCol = null;
      _botCount = _countLines(_C4Cell.bot, _grid);
      _isYouTurn = true;
    });
  }

  void _onContinueAfterWin() {
    setState(() {
      _phase = _C4Phase.trophy;
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
                final maxSide =
                    c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
                final boardSize = (maxSide * 0.9).clamp(240.0, 420.0);
                return Center(
                  child: SizedBox(
                    width: boardSize,
                    height: boardSize,
                    child: _BoardInteraction(
                      cols: _cols,
                      boardSize: boardSize,
                      enabled: _phase == _C4Phase.play && _isYouTurn && _dropCol == null,
                      onColChanged: (col) => setState(() => _hoverCol = col),
                      onColCleared: () => setState(() => _hoverCol = null),
                      onColTap: _onColumnTap,
                      child: CustomPaint(
                        painter: _C4BoardPainter(
                          grid: _grid,
                          hoverCol:
                              _phase == _C4Phase.play ? _hoverCol : null,
                          dropCol: _dropCol,
                          dropT: _dropT,
                        ),
                        size: Size(boardSize, boardSize),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_phase == _C4Phase.start)
          GameStartOverlay(
            title: 'CONNECT FOUR',
            subtitle: 'Get 4 in a row,\nyou vs Bot!',
            youScore: _yourCount,
            targetScore: _youTarget,
            instruction:
                'Tap a column to drop a disc. Get 4 of your colour in a row — horizontally, vertically or diagonally.',
            illustration: const BoyCharacter(pose: BoyPose.cueStick),
            onPlay: _onPlay,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        if (_phase == _C4Phase.win)
          GameWinOverlay(
            title: 'YOU WIN!',
            subtitle: 'FOUR IN A ROW!',
            scoreValue: _yourCount,
            scoreLabel: 'Lines Landed',
            statRows: [
              ('Moves', '${_moveBudget - _movesLeft}/$_moveBudget'),
              ('Bot', '$_botCount'),
            ],
            onContinue: _onContinueAfterWin,
          ),
        if (_phase == _C4Phase.trophy)
          GameTrophyOverlay(
            iconData: Icons.grid_4x4_rounded,
            iconGradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: _yourCount >= _youTarget ? 'Great Job!' : 'Keep Going!',
            subtitle: _yourCount >= _youTarget
                ? 'You landed 4 in a row.'
                : 'Try again — beat the bot first.',
            score: _score,
            statRows: [
              ('You', '$_yourCount'),
              ('Bot', '$_botCount'),
              ('Target', '$_youTarget'),
            ],
            onPlayAgain: _onPlayAgain,
            onBack: () => Navigator.of(context).maybePop(),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Interaction layer — converts pointer position to a column index and
// forwards taps. Falls back to a plain GestureDetector when running
// outside a mouse-region-supporting platform (e.g. touch devices).
// ────────────────────────────────────────────────────────────────────

class _BoardInteraction extends StatelessWidget {
  const _BoardInteraction({
    required this.cols,
    required this.boardSize,
    required this.enabled,
    required this.onColChanged,
    required this.onColCleared,
    required this.onColTap,
    required this.child,
  });

  final int cols;
  final double boardSize;
  final bool enabled;
  final ValueChanged<int> onColChanged;
  final VoidCallback onColCleared;
  final ValueChanged<int> onColTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cell = boardSize / cols;
    int colFrom(Offset local) =>
        (local.dx / cell).floor().clamp(0, cols - 1);
    return MouseRegion(
      onHover: (e) {
        if (!enabled) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onColChanged(colFrom(box.globalToLocal(e.position)));
      },
      onExit: (_) => onColCleared(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled
            ? (d) => onColTap(colFrom(d.localPosition))
            : null,
        child: child,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Board painter
// ────────────────────────────────────────────────────────────────────

class _C4BoardPainter extends CustomPainter {
  _C4BoardPainter({
    required this.grid,
    required this.hoverCol,
    required this.dropCol,
    required this.dropT,
  });

  final List<List<_C4Cell>> grid;
  final int? hoverCol;
  final int? dropCol;
  final double dropT;

  static const _frame = Color(0xFF1E3A8A);
  static const _frameLight = Color(0xFF3B82F6);
  static const _slot = Color(0xFF0B1226);
  static const _you = Color(0xFFEF4444);
  static const _youDark = Color(0xFF991B1B);
  static const _bot = Color(0xFFFACC15);
  static const _botDark = Color(0xFFCA8A04);

  static final _framePaint = Paint()..color = _frame;
  static final _slotPaint = Paint()..color = _slot;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = size.width * 0.04;
    final w = size.width - pad * 2;
    final cell = w / 7;
    final r = cell * 0.38;
    final rect = Rect.fromLTWH(pad, pad, w, size.height - pad * 2);

    final rr = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.04),
    );
    canvas.drawRRect(rr, _framePaint);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _frameLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 7; col++) {
        final c = Offset(
          pad + col * cell + cell / 2,
          pad + row * cell + cell / 2,
        );
        canvas.drawCircle(c, r, _slotPaint);
      }
    }

    if (hoverCol != null) {
      final c = Offset(
        pad + hoverCol! * cell + cell / 2,
        pad + cell / 2,
      );
      canvas.drawCircle(
        c,
        r * 0.9,
        Paint()..color = _you.withValues(alpha: 0.5),
      );
    }

    if (dropCol != null) {
      final c = Offset(
        pad + dropCol! * cell + cell / 2,
        pad + cell / 2 + (size.height - cell) * dropT,
      );
      _drawDisc(canvas, c, r, _you);
    }

    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 7; col++) {
        final v = grid[row][col];
        if (v == _C4Cell.empty) continue;
        if (dropCol == col) continue;
        final c = Offset(
          pad + col * cell + cell / 2,
          pad + row * cell + cell / 2,
        );
        _drawDisc(canvas, c, r, v == _C4Cell.you ? _you : _bot);
      }
    }
  }

  void _drawDisc(Canvas canvas, Offset center, double r, Color color) {
    final dark = color == _you ? _youDark : _botDark;
    canvas.drawCircle(
      Offset(center.dx + r * 0.12, center.dy + r * 0.18),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      Offset(center.dx - r * 0.35, center.dy - r * 0.35),
      r * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_C4BoardPainter old) =>
      old.hoverCol != hoverCol ||
      old.dropCol != dropCol ||
      old.dropT != dropT ||
      !_gridEqual(old.grid, grid);

  static bool _gridEqual(List<List<_C4Cell>> a, List<List<_C4Cell>> b) {
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
