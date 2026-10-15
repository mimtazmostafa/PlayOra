import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// Classic Mini Ludo — faithful to the canonical cross board.
///
/// Board geometry (15x15 grid, per Wikipedia Ludo):
///
///   ┌─────────────┐
///   │ YY │  Y↑   │ GG │     Y = Yellow base  G = Green base
///   │ YY │  Y↑   │ GG │     R = Red base     B = Blue base
///   │ YY │  ←──→ │ GG │     ↑↓←→ are arm
///   ├─────────────┤            columns (3-wide)
///   │  R→ │ HOME │ ←B │
///   ├─────────────┤
///   │ RR │  ↓R   │ BB │
///   │ RR │  ↓R   │ BB │
///   │ RR │       │ BB │
///   └─────────────┘
///
/// Each player has 4 tokens starting in their 3x3 yard. To enter the
/// board, a token must roll a 6. The first square of a player's path
/// is the cell just outside their yard (their "start" square).
///
/// The outer loop is 52 squares; once a token has walked 51 squares it
/// enters its own colored home stretch (5 squares) and then the
/// center triangle. A token with position == 57 has reached HOME.
///
/// 2-player mode here (Red vs Yellow). Same code path supports 4.
///
/// Controls:
///   * Tap "ROLL" button to roll the dice (animated 600ms).
///   * If only one token can move with the roll, it auto-moves.
///   * Otherwise tap a token to move it.
///   * 6 grants another turn. Capturing an opponent token sends it home.
class MiniLudoGame extends MiniGame {
  const MiniLudoGame({super.key, required super.callbacks});

  @override
  State<MiniLudoGame> createState() => _LudoState();
}

class _LudoState extends MiniGameState<MiniLudoGame>
    with SingleTickerProviderStateMixin {
  // ── Board geometry constants (canonical Ludo) ─────────────────────
  static const int _grid = 15;
  static const int _totalPlayers = 2;
  static const int _homeWinStep = 57; // 0..loopLen-1 outer, loopLen..loopLen+4 stretch, _homeWinStep = home

  /// Length of the outer loop. Computed once for the active player.
  static const int _loopLen = 54;

  late final Ticker _ticker;

  final Random _rng = Random();
  final List<_Token> _tokens = [];

  int _current = 0;
  int _lastRoll = 0;
  bool _diceAvailable = true;
  bool _rolling = false;
  int _score = 0;
  bool _gameOver = false;
  int _wonPlayer = -1;
  double _pulse = 0; // 0..1 highlight pulse

  @override
  void initState() {
    super.initState();
    _resetTokens();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(0);
      _updateStats();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (_rolling) {
      // Re-trigger a frame for dice flicker.
      setState(() {});
    }
    if (_pulse > 0) {
      setState(() => _pulse = max(0, _pulse - 0.025));
    }
  }

  void _resetTokens() {
    _tokens.clear();
    for (var p = 0; p < _totalPlayers; p++) {
      for (var t = 0; t < 4; t++) {
        _tokens.add(_Token(player: p, index: t, position: -1));
      }
    }
  }

  // ── Color palette (canonical Ludo: red, yellow, green, blue) ─────
  static const _palette = <Color>[
    Color(0xFFEF4444), // red
    Color(0xFFFACC15), // yellow
    Color(0xFF22C55E), // green
    Color(0xFF3B82F6), // blue
  ];

  Color _color(int p) => _palette[p % _palette.length];

  // ── Path geometry helpers ────────────────────────────────────────

  /// Returns the outer 54-cell loop for `player`. Player 0 (Red) is
  /// the canonical cross walk; other players rotate 180° about (7,7).
  ///
  /// Loop walk (clockwise):
  ///   A) left col 0, rows 6→0
  ///   B) top row 0, cols 1→6
  ///   C) center col 6, rows 1→6
  ///   D) middle row 6, cols 7→14
  ///   E) right col 14, rows 7→14
  ///   F) bottom row 14, cols 13→8
  ///   G) center col 8, rows 13→8
  ///   H) middle row 8, cols 7→1
  /// = 7+6+6+8+8+6+6+7 = 54 cells.
  List<Point<int>> _loopForPlayer(int player) {
    final pts = <Point<int>>[];
    for (var r = 6; r >= 0; r--) {
      pts.add(Point(0, r));
    }
    for (var c = 1; c <= 6; c++) {
      pts.add(Point(c, 0));
    }
    for (var r = 1; r <= 6; r++) {
      pts.add(Point(6, r));
    }
    for (var c = 7; c <= 14; c++) {
      pts.add(Point(c, 6));
    }
    for (var r = 7; r <= 14; r++) {
      pts.add(Point(14, r));
    }
    for (var c = 13; c >= 8; c--) {
      pts.add(Point(c, 14));
    }
    for (var r = 13; r >= 8; r--) {
      pts.add(Point(8, r));
    }
    for (var c = 7; c >= 1; c--) {
      pts.add(Point(c, 8));
    }
    if (player == 0) return pts;
    return pts
        .map((p) => Point(14 - p.x, 14 - p.y))
        .toList(growable: false);
  }

  // ── Token movement ───────────────────────────────────────────────
  void _roll() {
    if (!_diceAvailable || _rolling || _gameOver) return;
    setState(() {
      _rolling = true;
      _lastRoll = 1 + _rng.nextInt(6);
      _diceAvailable = false;
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _rolling = false);
      haptic(HapticFeedbackType.medium);
      _applyRoll();
    });
  }

  /// Returns true if the given token is movable with the current roll.
  bool _canMove(_Token t) {
    if (t.player != _current) return false;
    if (t.position == -1) return _lastRoll == 6;
    if (t.position >= _homeWinStep) return false; // already home
    return t.position + _lastRoll <= _homeWinStep;
  }

  void _applyRoll() {
    final movable = _tokens.where(_canMove).toList();
    if (movable.isEmpty) {
      _nextPlayer();
      return;
    }
    if (movable.length == 1) {
      _moveToken(movable.first);
    } else {
      // Highlight movable tokens; player picks one.
      setState(() => _pulse = 1.0);
      _updateStats();
    }
  }

  void _onTapToken(_Token t) {
    if (_gameOver || _rolling) return;
    if (t.player != _current) return;
    if (!_canMove(t)) return;
    _moveToken(t);
  }

  void _moveToken(_Token t) {
    setState(() {
      if (t.position == -1) {
        t.position = 0;
      } else {
        t.position += _lastRoll;
      }
      // Check capture: if landed on a square with one opponent, send
      // opponent home.
      if (t.position >= 0 && t.position < _homeWinStep) {
        final cell = _cellOf(t.player, t.position);
        if (cell != null) {
          final opp = _opponentAt(t.player, cell);
          if (opp != null) {
            opp.position = -1;
            _score += 50;
            haptic(HapticFeedbackType.heavy);
          }
        }
      }
      _pulse = 0;
    });
    _score += _lastRoll;
    haptic(HapticFeedbackType.light);
    reportScore(_score);
    _updateStats();

    // Check win first.
    final allHome = _tokens
        .where((tk) => tk.player == t.player)
        .every((tk) => tk.position >= _homeWinStep);
    if (allHome) {
      _win(t.player);
      return;
    }
    if (_lastRoll == 6) {
      // Bonus turn.
      setState(() => _diceAvailable = true);
      _updateStats();
    } else {
      _nextPlayer();
    }
  }

  /// For a token of `player` at position `position`, returns its cell
  /// (col, row) on the 15x15 grid. position 0..loopLen-1 maps to the
  /// outer loop; loopLen..loopLen+4 maps to the home stretch;
  /// _homeWinStep == won.
  Point<int>? _cellOf(int player, int position) {
    if (position >= _homeWinStep) return null; // already home
    if (position < 0) return null; // in yard
    final loop = _loopForPlayer(player);
    if (position < loop.length) return loop[position];
    // On the home stretch: column inside the player's arm. For
    // 2-player: each player's stretch is col 7 (between arms).
    final stretchStep = position - _loopLen; // 0..4
    if (stretchStep >= 0 && stretchStep < 5) {
      // Red home stretch: col=7, rows 7..3 (top arm, going toward home).
      // Yellow home stretch: col=7, rows 7..11 (bottom arm).
      final row = player == 0 ? 7 - stretchStep : 7 + stretchStep;
      return Point(7, row);
    }
    return null;
  }

  _Token? _opponentAt(int myPlayer, Point<int> cell) {
    for (final t in _tokens) {
      if (t.player == myPlayer) continue;
      if (t.position < 0 || t.position >= _homeWinStep) continue;
      final c = _cellOf(t.player, t.position);
      if (c == cell) return t;
    }
    return null;
  }

  void _nextPlayer() {
    setState(() {
      _current = (_current + 1) % _totalPlayers;
      _diceAvailable = true;
      _pulse = 0;
    });
    _updateStats();
  }

  void _win(int player) {
    setState(() {
      _gameOver = true;
      _wonPlayer = player;
    });
    haptic(HapticFeedbackType.heavy);
    reportScore(_score + 500);
    reportStats('${_colorName(player)} wins!');
    reportGameOver();
  }

  String _colorName(int p) =>
      p == 0 ? 'Red' : (p == 1 ? 'Yellow' : 'P${p + 1}');

  void _restart() {
    setState(() {
      _resetTokens();
      _current = 0;
      _lastRoll = 0;
      _diceAvailable = true;
      _rolling = false;
      _score = 0;
      _gameOver = false;
      _wonPlayer = -1;
    });
    reportScore(0);
    reportStats('Tap ROLL to start');
  }

  void _updateStats() {
    if (_gameOver) {
      reportStats('${_colorName(_wonPlayer)} wins!');
      return;
    }
    final turn = _colorName(_current);
    if (_rolling) {
      reportStats('$turn · Rolling…');
    } else if (_diceAvailable) {
      reportStats("$turn · Tap to roll");
    } else {
      reportStats("$turn · Roll $_lastRoll");
    }
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kGamePanel(Theme.of(context).brightness),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _color(_current),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _gameOver
                        ? '${_colorName(_wonPlayer)} wins!'
                        : "${_colorName(_current)}'s turn",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Score $_score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Restart',
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final cell = (c.biggest.shortestSide / _grid)
                      .clamp(14.0, 30.0);
                  return Center(
                    child: SizedBox(
                      width: cell * _grid,
                      height: cell * _grid,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => _onBoardTap(
                                  d.localPosition, cell),
                              child: CustomPaint(
                                painter: _LudoPainter(
                                  tokens: _tokens,
                                  cell: cell,
                                  currentPlayer: _current,
                                  pulse: _pulse,
                                  palette: _palette,
                                  lastRoll: _lastRoll,
                                  rolling: _rolling,
                                ),
                              ),
                            ),
                          ),
                          if (_gameOver)
                            Center(
                              child: _WinBanner(
                                color: _color(_wonPlayer),
                                label: '${_colorName(_wonPlayer)} wins!',
                                onPlayAgain: _restart,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _gameOver ? null : _roll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 22),
                decoration: BoxDecoration(
                  color: _gameOver
                      ? Colors.white12
                      : kGameAccent(Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _rolling
                          ? Icons.casino_rounded
                          : Icons.casino_outlined,
                      color: _gameOver
                          ? Colors.white24
                          : const Color(0xFF00281A),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _rolling
                          ? 'Rolling…'
                          : (_gameOver ? 'Game over' : 'Roll dice'),
                      style: TextStyle(
                        color: _gameOver
                            ? Colors.white24
                            : const Color(0xFF00281A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onBoardTap(Offset p, double cell) {
    if (_gameOver || _rolling) return;
    final hitRadius = cell * 0.6;
    _Token? best;
    double bestDist = hitRadius;
    for (final t in _tokens) {
      if (t.player != _current) continue;
      if (t.position < 0 || t.position >= _homeWinStep) continue;
      final tc = _cellOf(t.player, t.position);
      if (tc == null) continue;
      final center = Offset(
        tc.x * cell + cell / 2,
        tc.y * cell + cell / 2,
      );
      final d = (center - p).distance;
      if (d < bestDist) {
        bestDist = d;
        best = t;
      }
    }
    if (best != null) _onTapToken(best);
  }
}

class _Token {
  _Token({
    required this.player,
    required this.index,
    required this.position,
  });
  final int player;
  final int index;
  int position; // -1 = yard, 0..loopLen-1 = loop, loopLen..loopLen+4 = stretch, _homeWinStep = home
}

// ───────────────────────────────────────────────────────────────────
// Painter
// ───────────────────────────────────────────────────────────────────

class _LudoPainter extends CustomPainter {
  _LudoPainter({
    required this.tokens,
    required this.cell,
    required this.currentPlayer,
    required this.pulse,
    required this.palette,
    required this.lastRoll,
    required this.rolling,
  });

  final List<_Token> tokens;
  final double cell;
  final int currentPlayer;
  final double pulse;
  final List<Color> palette;
  final int lastRoll;
  final bool rolling;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBoard(canvas, size);
    _drawLoopCells(canvas, size);
    _drawHomeTriangles(canvas, size);
    _drawTokens(canvas, size);
    _drawDiceBadge(canvas, size);
  }

  void _drawBoard(Canvas canvas, Size size) {
    // Wood background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5DEB3), Color(0xFFE8C99B)],
        ).createShader(Offset.zero & size),
    );
    // Soft border.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xFF6D4C41)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Yard backgrounds (2 corners for 2-player mode).
    final yardPaint = Paint()..style = PaintingStyle.fill;
    yardPaint.color = palette[0].withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, cell * 6, cell * 6), yardPaint);
    yardPaint.color = palette[1].withValues(alpha: 0.55);
    canvas.drawRect(
        Rect.fromLTWH(cell * 9, cell * 9, cell * 6, cell * 6), yardPaint);

    // Center home area (6x6 from (6,6) to (11,11)).
    final home = Rect.fromLTWH(cell * 6, cell * 6, cell * 6, cell * 6);
    canvas.drawRect(home, Paint()..color = Colors.white.withValues(alpha: 0.3));

    // Grid lines.
    final gridLine = Paint()
      ..color = const Color(0xFF6D4C41).withValues(alpha: 0.4)
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 15; i++) {
      canvas.drawLine(
        Offset(i * cell, 0),
        Offset(i * cell, 15 * cell),
        gridLine,
      );
      canvas.drawLine(
        Offset(0, i * cell),
        Offset(15 * cell, i * cell),
        gridLine,
      );
    }
  }

  void _drawLoopCells(Canvas canvas, Size size) {
    // Draw a slightly tinted square on each loop cell so the path is
    // visible. We render both players' loops; where they overlap the
    // later draw wins.
    final loop0 = _makeLoop(0);
    final loop1 = _makeLoop(1);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final p in loop0) {
      _drawSquare(canvas, p.x * cell, p.y * cell, cell, paint.color);
    }
    for (final p in loop1) {
      _drawSquare(canvas, p.x * cell, p.y * cell, cell, paint.color);
    }
    // Home-stretch cells (col 7, rows 3..7 for red, rows 7..11 for yellow).
    final stretchPaint = palette[0].withValues(alpha: 0.55);
    for (var row = 3; row <= 7; row++) {
      _drawSquare(canvas, 7 * cell, row * cell, cell, stretchPaint);
    }
    final stretchPaint2 = palette[1].withValues(alpha: 0.55);
    for (var row = 7; row <= 11; row++) {
      _drawSquare(canvas, 7 * cell, row * cell, cell, stretchPaint2);
    }
  }

  void _drawSquare(Canvas canvas, double x, double y, double cell, Color c) {
    final inset = cell * 0.06;
    canvas.drawRect(
      Rect.fromLTWH(x + inset, y + inset, cell - 2 * inset, cell - 2 * inset),
      Paint()..color = c,
    );
  }

  void _drawHomeTriangles(Canvas canvas, Size size) {
    final cx = cell * 7.5;
    final cy = cell * 7.5;
    final r = cell * 3;
    void tri(Color color, double rotation) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rotation);
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(r, -r)
        ..lineTo(r, r)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
      canvas.restore();
    }

    tri(palette[0], 0);
    tri(palette[1], pi);
  }

  void _drawTokens(Canvas canvas, Size size) {
    final grouped = <String, List<_Token>>{};
    for (final t in tokens) {
      final key = '${t.player}-${t.position}';
      grouped.putIfAbsent(key, () => []).add(t);
    }
    for (final entry in grouped.entries) {
      final list = entry.value;
      final rep = list.first;
      if (rep.position < 0) {
        _drawYardTokens(canvas, list);
      } else if (rep.position >= 57) {
        _drawHomeToken(canvas, list);
      } else {
        _drawBoardTokens(canvas, list);
      }
    }
  }

  void _drawYardTokens(Canvas canvas, List<_Token> list) {
    final p = list.first.player;
    final baseX = (p == 0) ? 0.0 : cell * 9;
    final baseY = (p == 0) ? 0.0 : cell * 9;
    final color = palette[p];
    final positions = [
      Offset(baseX + cell * 2, baseY + cell * 2),
      Offset(baseX + cell * 4, baseY + cell * 2),
      Offset(baseX + cell * 2, baseY + cell * 4),
      Offset(baseX + cell * 4, baseY + cell * 4),
    ];
    final isActive = p == currentPlayer;
    for (var i = 0; i < list.length; i++) {
      final pos = positions[list[i].index % 4];
      _drawTokenCircle(canvas, pos, color,
          pulseRing: isActive ? pulse : 0);
    }
  }

  void _drawBoardTokens(Canvas canvas, List<_Token> list) {
    final p = list.first.player;
    final loop = _makeLoop(p);
    final pos = list.first.position;
    Point<int>? cellPt;
    if (pos < loop.length) {
      cellPt = loop[pos];
    } else {
      final stretchStep = pos - loop.length;
      if (stretchStep >= 0 && stretchStep < 5) {
        final row = p == 0 ? 7 - stretchStep : 7 + stretchStep;
        cellPt = Point(7, row);
      }
    }
    if (cellPt == null) return;
    final cx = cellPt.x * cell + cell / 2;
    final cy = cellPt.y * cell + cell / 2;
    final n = list.length;
    final spreadRadius = (n > 1) ? cell * 0.22 : 0.0;
    for (var i = 0; i < n; i++) {
      double dx = 0, dy = 0;
      if (n == 2) {
        dx = (i == 0 ? -1 : 1) * spreadRadius;
      } else if (n == 3) {
        final a = i * 2 * pi / 3;
        dx = cos(a) * spreadRadius;
        dy = sin(a) * spreadRadius;
      } else if (n >= 4) {
        final a = (i + 0.5) * 2 * pi / n;
        dx = cos(a) * spreadRadius;
        dy = sin(a) * spreadRadius;
      }
      _drawTokenCircle(canvas, Offset(cx + dx, cy + dy), palette[p],
          pulseRing: p == currentPlayer ? pulse : 0);
    }
  }

  void _drawHomeToken(Canvas canvas, List<_Token> list) {
    final cx = cell * 7.5;
    final cy = cell * 7.5;
    final p = list.first.player;
    final color = palette[p];
    for (var i = 0; i < list.length; i++) {
      final dx = (i - list.length / 2.0) * cell * 0.4;
      canvas.drawCircle(
        Offset(cx + dx, cy),
        cell * 0.18,
        Paint()..color = color,
      );
    }
  }

  List<Point<int>> _makeLoop(int player) {
    final pts = <Point<int>>[];
    for (var r = 6; r >= 0; r--) {
      pts.add(Point(0, r));
    }
    for (var c = 1; c <= 6; c++) {
      pts.add(Point(c, 0));
    }
    for (var r = 1; r <= 6; r++) {
      pts.add(Point(6, r));
    }
    for (var c = 7; c <= 14; c++) {
      pts.add(Point(c, 6));
    }
    for (var r = 7; r <= 14; r++) {
      pts.add(Point(14, r));
    }
    for (var c = 13; c >= 8; c--) {
      pts.add(Point(c, 14));
    }
    for (var r = 13; r >= 8; r--) {
      pts.add(Point(8, r));
    }
    for (var c = 7; c >= 1; c--) {
      pts.add(Point(c, 8));
    }
    if (player == 0) return pts;
    return pts.map((p) => Point(14 - p.x, 14 - p.y)).toList();
  }

  void _drawTokenCircle(
    Canvas canvas,
    Offset c,
    Color color, {
    required double pulseRing,
  }) {
    final r = cell * 0.30;
    canvas.drawCircle(
      c + const Offset(1, 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(
      c,
      r,
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
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    if (pulseRing > 0) {
      canvas.drawCircle(
        c,
        r + 4 + pulseRing * 6,
        Paint()
          ..color = color.withValues(alpha: 0.6 * (1 - pulseRing))
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.38),
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _drawDiceBadge(Canvas canvas, Size size) {
    if (lastRoll == 0 && !rolling) return;
    final sz = cell * 2.4;
    final rect = Rect.fromLTWH(
      cell * 12.2,
      cell * 0.4,
      sz,
      sz,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = Colors.black87
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    // While rolling, flicker face at 6 fps.
    final face = rolling ? ((DateTime.now().millisecondsSinceEpoch ~/ 80) % 6 + 1) : lastRoll;
    _drawDiceDots(canvas, rect, face);
  }

  void _drawDiceDots(Canvas canvas, Rect rect, int face) {
    final paint = Paint()..color = Colors.black87;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final r = rect.width * 0.07;
    void dot(double x, double y) {
      canvas.drawCircle(Offset(x, y), r, paint);
    }

    switch (face) {
      case 1:
        dot(cx, cy);
        break;
      case 2:
        dot(rect.left + rect.width * 0.30, rect.top + rect.height * 0.30);
        dot(rect.left + rect.width * 0.70, rect.top + rect.height * 0.70);
        break;
      case 3:
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.28);
        dot(cx, cy);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.72);
        break;
      case 4:
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.28);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.28);
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.72);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.72);
        break;
      case 5:
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.28);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.28);
        dot(cx, cy);
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.72);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.72);
        break;
      case 6:
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.25);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.25);
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.50);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.50);
        dot(rect.left + rect.width * 0.28, rect.top + rect.height * 0.75);
        dot(rect.left + rect.width * 0.72, rect.top + rect.height * 0.75);
        break;
    }
  }

  @override
  bool shouldRepaint(_LudoPainter old) =>
      old.cell != cell ||
      old.currentPlayer != currentPlayer ||
      old.pulse != pulse ||
      old.lastRoll != lastRoll ||
      old.rolling != rolling ||
      !_tokensEqual(old.tokens, tokens);

  static bool _tokensEqual(List<_Token> a, List<_Token> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].position != b[i].position ||
          a[i].player != b[i].player) {
        return false;
      }
    }
    return true;
  }
}

// ───────────────────────────────────────────────────────────────────
// Win banner
// ───────────────────────────────────────────────────────────────────

class _WinBanner extends StatelessWidget {
  const _WinBanner({
    required this.color,
    required this.label,
    required this.onPlayAgain,
  });
  final Color color;
  final String label;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 56),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onPlayAgain,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Play Again'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
