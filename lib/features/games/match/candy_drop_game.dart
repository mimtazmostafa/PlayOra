import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/utils/random_utils.dart';
import '../game_widgets.dart';
import '../mini_game.dart';

/// **Candy Drop** — A match-3 candy puzzle.
///
/// Inspired by the actual Candy Drop match-3 style (tap adjacent
/// candies to swap, match 3+ in a row or column, gravity cascade,
/// refill from top, score to a level target within a limited move
/// budget).
///
/// Layout:
///   * 8 columns × 9 rows of candies.
///   * Six candy "flavors": cherry-red, lemon-yellow, lime-green,
///     blue-raspberry, grape-purple, orange-tangerine — each rendered
///     as a glossy round candy with a kawaii face.
///   * Top: held-by-the-finger "dropper" preview row showing the
///     next 3 candies to spawn from above (one at a time).
///   * Bottom: 3 booster buttons + level progress bar.
///
/// Rules (matching the popular Candy Drop / Candy Crush genre):
///   * Tap a candy, then tap an orthogonal neighbor to swap.
///     If the swap makes any 3+ match, commit; otherwise swap back.
///   * 4 in a row → striped candy (clears its row OR column when
///     matched later).
///   * 5 in a row → color bomb (clears ALL candies of one color when
///     swapped with that color).
///   * Match 3 / 4 / 5 scoring: 30 / 80 / 200 points.
///   * Level target: clear `targetScore` points within `moveLimit`
///     moves. Excess moves beyond limit also drop per-move bonus.
///
/// Visuals:
///   * Vibrant candy-shop palette, gloss highlights, animated
///     swap-then-match motion, gravity drop with ease-out,
///     sparkle particles on clear, combo counter for cascades.
class CandyDropGame extends MiniGame {
  const CandyDropGame({
    super.key,
    required super.callbacks,
    this.level = 1,
    this.dailyChallenge = false,
  });

  final int level;
  final bool dailyChallenge;

  @override
  State<CandyDropGame> createState() => _CandyDropState();
}

// ─────────────────────────────────────────────────────────────────
// Candy flavour definitions
// ─────────────────────────────────────────────────────────────────

class _FlavorPalette {
  const _FlavorPalette({
    required this.body,
    required this.highlight,
    required this.shadow,
    required this.outline,
    required this.accent,
  });
  final Color body;
  final Color highlight;
  final Color shadow;
  final Color outline;
  final Color accent;
}

const List<_FlavorPalette> _kFlavors = [
  // cherry red
  _FlavorPalette(
    body: Color(0xFFFF4D6D),
    highlight: Color(0xFFFFB1C1),
    shadow: Color(0xFFB0253D),
    outline: Color(0xFF591220),
    accent: Color(0xFFFFE0E5),
  ),
  // lemon yellow
  _FlavorPalette(
    body: Color(0xFFFFD23F),
    highlight: Color(0xFFFFEFAD),
    shadow: Color(0xFFB97A00),
    outline: Color(0xFF4A2E00),
    accent: Color(0xFFFFF8DD),
  ),
  // lime green
  _FlavorPalette(
    body: Color(0xFF8BC34A),
    highlight: Color(0xFFD4EB9F),
    shadow: Color(0xFF557A1F),
    outline: Color(0xFF26400C),
    accent: Color(0xFFE9F7CF),
  ),
  // blue raspberry
  _FlavorPalette(
    body: Color(0xFF38BDF8),
    highlight: Color(0xFFBCE6FB),
    shadow: Color(0xFF1565A8),
    outline: Color(0xFF062E55),
    accent: Color(0xFFE0F4FE),
  ),
  // grape purple
  _FlavorPalette(
    body: Color(0xFFB388FF),
    highlight: Color(0xFFE9D5FF),
    shadow: Color(0xFF6B21A8),
    outline: Color(0xFF2A0B5A),
    accent: Color(0xFFF3E8FF),
  ),
  // orange tangerine
  _FlavorPalette(
    body: Color(0xFFFF8C2B),
    highlight: Color(0xFFFFC78A),
    shadow: Color(0xFFB85105),
    outline: Color(0xFF5C2400),
    accent: Color(0xFFFFE5C2),
  ),
];

/// Candy "types" — flavour or special. We use one byte per cell
/// (0..5 normal, 6 horizontal striped, 7 vertical striped, 8 color
/// bomb). 0xff means empty.
const int _kEmpty = 0xff;
const int _kStripedH = 6;
const int _kStripedV = 7;
const int _kBomb = 8;

// ─────────────────────────────────────────────────────────────────
// Level config
// ─────────────────────────────────────────────────────────────────

class _LevelConfig {
  const _LevelConfig({
    required this.moveLimit,
    required this.targetScore,
    required this.colors,
  });
  final int moveLimit;
  final int targetScore;
  final int colors;
}

_LevelConfig _configForLevel(int level) {
  // Soft ramp: more colors and bigger targets as levels go up.
  final t = level.clamp(1, 99);
  final colors = (4 + (t / 5).floor()).clamp(4, 6);
  final moves = 24 + (t * 2);
  final target = 800 + t * 250;
  return _LevelConfig(
    moveLimit: moves,
    targetScore: target,
    colors: colors,
  );
}

// ─────────────────────────────────────────────────────────────────
// Game state
// ─────────────────────────────────────────────────────────────────

class _CandyDropState extends MiniGameState<CandyDropGame>
    with TickerProviderStateMixin {
  static const int _cols = 8;
  static const int _rows = 9;

  late final Random _rng = widget.dailyChallenge
      ? Random(dailySeedFor('candy-drop'))
      : Random();
  late final _LevelConfig _level = _configForLevel(widget.level);

  // Board: grid[row][col] = byte (flavor/special/empty).
  late List<List<int>> _grid;
  // Animating cells: per-cell state for swap/gravity/clear tweens.
  // Each row maps col → cell anim state.
  late List<List<_CellAnim>> _anims;
  // Special candy placements created this turn — used for spawn flags.
  final Set<int> _stripesCreated = {};

  // Match-3 highlighting glow.
  final Set<int> _matched = {}; // packed r*_cols + c

  // Score / progress.
  int _score = 0;
  int _movesLeft = 0;
  int _targetScore = 0;
  bool _gameOver = false;
  bool _won = false;
  bool _animating = false;
  int _comboCount = 0;

  // Selected cell (for swap).
  int? _selectedRow;
  int? _selectedCol;

  // Boosters.
  int _bombCharges = 3;
  int _shuffleCharges = 2;
  int _hintCharges = 3;

  // Next-piece preview queue.
  late List<int> _nextQueue;

  // Anim controllers.
  late final AnimationController _idleCtrl;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Particle FX.
  final List<_Spark> _sparks = [];
  final List<_Floater> _floaters = [];

  // Layout cache.
  double _cellSize = 36;
  double _boardLeft = 0;
  double _boardTop = 0;

  // Hint flash.
  double _hintFlash = 0;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _ticker = createTicker(_onTick)..start();
    _movesLeft = _level.moveLimit;
    _targetScore = _level.targetScore;
    _grid = _makeInitialGrid();
    _anims = _makeAnimGrid();
    _nextQueue = _makeNextQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats(_statsLine());
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Stats line for HUD subtitle
  // ─────────────────────────────────────────────────────────────
  String _statsLine() {
    return 'Moves $_movesLeft  •  Target $_targetScore';
  }

  // ─────────────────────────────────────────────────────────────
  // Grid generation — initial board with no pre-existing matches.
  // ─────────────────────────────────────────────────────────────
  List<List<int>> _makeInitialGrid() {
    final g = List.generate(_rows, (_) => List.filled(_cols, 0));
    var attempts = 0;
    while (attempts < 200) {
      attempts++;
      for (var r = 0; r < _rows; r++) {
        for (var c = 0; c < _cols; c++) {
          var pick = _rng.nextInt(_level.colors);
          // Avoid creating same-color in a 3-in-a-row already placed.
          if (c >= 2 &&
              g[r][c - 1] == pick &&
              g[r][c - 2] == pick) {
            pick = (pick + 1 + _rng.nextInt(_level.colors - 1)) %
                _level.colors;
          }
          if (r >= 2 &&
              g[r - 1][c] == pick &&
              g[r - 2][c] == pick) {
            pick = (pick + 1 + _rng.nextInt(_level.colors - 1)) %
                _level.colors;
          }
          g[r][c] = pick;
        }
      }
      // If by some bad luck a match exists, shuffle colours of any
      // matched triple until none remain.
      if (!_anyMatches(g)) break;
    }
    return g;
  }

  List<List<_CellAnim>> _makeAnimGrid() {
    return List.generate(
      _rows,
      (_) => List.generate(_cols, (_) => _CellAnim()),
    );
  }

  List<int> _makeNextQueue() {
    return List.generate(
      3,
      (_) => _rng.nextInt(_level.colors),
    );
  }

  bool _anyMatches(List<List<int>> g) {
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (_matchAt(g, r, c)) return true;
      }
    }
    return false;
  }

  bool _matchAt(List<List<int>> g, int r, int c) {
    final v = g[r][c];
    if (v == _kEmpty || v >= _kStripedH) return false;
    if (c >= 2 &&
        g[r][c - 1] == v &&
        g[r][c - 2] == v) {
      return true;
    }
    if (r >= 2 &&
        g[r - 1][c] == v &&
        g[r - 2][c] == v) {
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // Tap / drag / swap
  // ─────────────────────────────────────────────────────────────

  void _onCellTap(int row, int col) {
    if (_gameOver) return;
    if (_animating) return;
    if (_grid[row][col] == _kEmpty) return;

    if (_selectedRow == null) {
      setState(() {
        _selectedRow = row;
        _selectedCol = col;
        haptic(HapticFeedbackType.light);
      });
      return;
    }
    final sr = _selectedRow!;
    final sc = _selectedCol!;
    if (sr == row && sc == col) {
      setState(() {
        _selectedRow = null;
        _selectedCol = null;
      });
      return;
    }
    final dr = (row - sr).abs();
    final dc = (col - sc).abs();
    final adjacent = (dr + dc) == 1;
    if (!adjacent) {
      setState(() {
        _selectedRow = row;
        _selectedCol = col;
        haptic(HapticFeedbackType.light);
      });
      return;
    }
    _trySwap(sr, sc, row, col);
  }

  Future<void> _trySwap(int r1, int c1, int r2, int c2) async {
    _animating = true;
    final swapped = await _animateSwap(r1, c1, r2, c2);
    if (!swapped) {
      _animating = false;
      setState(() {
        _selectedRow = null;
        _selectedCol = null;
      });
      return;
    }
    _swapCells(r1, c1, r2, c2);
    final matches = _findAllMatches();
    if (matches.isEmpty) {
      // Swap back.
      await _animateSwap(r1, c1, r2, c2);
      _swapCells(r1, c1, r2, c2);
      _animating = false;
      setState(() {
        _selectedRow = null;
        _selectedCol = null;
      });
      haptic(HapticFeedbackType.light);
      return;
    }
    _selectedRow = null;
    _selectedCol = null;
    _movesLeft = max(0, _movesLeft - 1);
    _comboCount = 0;
    await _resolveBoard();
    _checkEnd();
    _animating = false;
    reportScore(_score);
    reportStats(_statsLine());
  }

  void _swapCells(int r1, int c1, int r2, int c2) {
    final t = _grid[r1][c1];
    _grid[r1][c1] = _grid[r2][c2];
    _grid[r2][c2] = t;
  }

  /// Animate two cells swapping positions and return when done.
  /// Returns false if the cells were the same (no-op).
  Future<bool> _animateSwap(int r1, int c1, int r2, int c2) async {
    if (r1 == r2 && c1 == c2) return false;
    final a = _cellCenter(r1, c1);
    final b = _cellCenter(r2, c2);
    final completer = _Completer();
    final startA = _anims[r1][c1].offset;
    final startB = _anims[r2][c2].offset;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    ctrl.addListener(() {
      final t = Curves.easeInOutCubic.transform(ctrl.value);
      setState(() {
        _anims[r1][c1].offset = Offset.lerp(startA, b - a, t)!;
        _anims[r2][c2].offset = Offset.lerp(startB, a - b, t)!;
        _anims[r1][c1].scale = 1.0 + 0.12 * sin(t * pi);
        _anims[r2][c2].scale = 1.0 + 0.12 * sin(t * pi);
      });
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        ctrl.dispose();
        completer.complete();
      }
    });
    ctrl.forward();
    await completer.future;
    // Snap back to grid-aligned.
    setState(() {
      _anims[r1][c1].offset = Offset.zero;
      _anims[r2][c2].offset = Offset.zero;
      _anims[r1][c1].scale = 1.0;
      _anims[r2][c2].scale = 1.0;
    });
    return true;
  }

  Offset _cellCenter(int r, int c) {
    return Offset(
      _boardLeft + c * _cellSize + _cellSize / 2,
      _boardTop + r * _cellSize + _cellSize / 2,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Match detection — horizontal & vertical lines of 3+.
  // ─────────────────────────────────────────────────────────────────────────────

  Set<int> _findAllMatches() {
    final result = <int>{};
    // Horizontal runs.
    for (var r = 0; r < _rows; r++) {
      var c = 0;
      while (c < _cols) {
        final v = _grid[r][c];
        if (v == _kEmpty || v >= _kStripedH) {
          c++;
          continue;
        }
        var k = c + 1;
        while (k < _cols && _grid[r][k] == v) {
          k++;
        }
        final runLen = k - c;
        if (runLen >= 3) {
          for (var i = c; i < k; i++) {
            result.add(r * _cols + i);
          }
        }
        c = k;
      }
    }
    // Vertical runs.
    for (var c = 0; c < _cols; c++) {
      var r = 0;
      while (r < _rows) {
        final v = _grid[r][c];
        if (v == _kEmpty || v >= _kStripedH) {
          r++;
          continue;
        }
        var k = r + 1;
        while (k < _rows && _grid[k][c] == v) {
          k++;
        }
        final runLen = k - r;
        if (runLen >= 3) {
          for (var i = r; i < k; i++) {
            result.add(i * _cols + c);
          }
        }
        r = k;
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // Resolve: clear → gravity → refill → loop until stable.
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _resolveBoard() async {
    var cascade = 0;
    while (true) {
      final matches = _findAllMatches();
      if (matches.isEmpty) break;
      cascade++;
      _comboCount = cascade;
      _matched
        ..clear()
        ..addAll(matches);
      final pts = await _animateAndScore(matches, cascade);
      _score += pts;
      reportScore(_score);
      // Spawn specials based on match shapes (5 → bomb, 4 → stripe).
      _spawnSpecialsFromMatches(matches);
      // Clear matched cells.
      for (final key in matches) {
        final r = key ~/ _cols;
        final c = key % _cols;
        _grid[r][c] = _kEmpty;
      }
      haptic(HapticFeedbackType.medium);
      await Future.delayed(const Duration(milliseconds: 80));
      // Gravity.
      await _animateGravity();
      // Refill.
      _refillBoard();
      await Future.delayed(const Duration(milliseconds: 220));
    }
  }

  Future<int> _animateAndScore(Set<int> matches, int cascade) async {
    // Use the running combo counter for escalating bonus.
    final pts = matches.length * 30 + (_comboCount * 60);
    // Spawn sparkle at each match center (approximate).
    final centers = <Offset>[];
    for (final key in matches) {
      final r = key ~/ _cols;
      final c = key % _cols;
      centers.add(_cellCenter(r, c));
    }
    if (centers.isNotEmpty) {
      final mid = Offset(
        centers.map((o) => o.dx).reduce((a, b) => a + b) / centers.length,
        centers.map((o) => o.dy).reduce((a, b) => a + b) / centers.length,
      );
      _floaters.add(_Floater(
        x: mid.dx,
        y: mid.dy,
        text: cascade > 1 ? 'x$cascade COMBO!' : '+$pts',
        color: cascade > 1
            ? const Color(0xFFFF5BAA)
            : const Color(0xFFFFD23F),
        life: 1.4,
      ));
      _spawnSparks(mid, matches.length);
    }
    // Animate matched cells: shrink + fade.
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    final completer = _Completer();
    ctrl.addListener(() {
      final t = ctrl.value;
      setState(() {
        for (final key in matches) {
          final r = key ~/ _cols;
          final c = key % _cols;
          _anims[r][c].scale = 1.0 - t;
          _anims[r][c].flash = (1.0 - t).clamp(0.0, 1.0);
        }
      });
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        ctrl.dispose();
        completer.complete();
      }
    });
    ctrl.forward();
    await completer.future;
    return pts;
  }

  void _spawnSparks(Offset center, int count) {
    final n = count.clamp(4, 18);
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final sp = 90 + _rng.nextDouble() * 120;
      _sparks.add(_Spark(
        x: center.dx,
        y: center.dy,
        vx: cos(a) * sp,
        vy: sin(a) * sp - 30,
        life: 1.0,
        color: i.isEven
            ? const Color(0xFFFFD23F)
            : const Color(0xFFFF8FA3),
        size: 3.5 + _rng.nextDouble() * 2.5,
        star: true,
      ));
    }
  }

  void _spawnSpecialsFromMatches(Set<int> matches) {
    // Find runs of 4+ horizontal/vertical and turn the center into a
    // stripe; 5+ into a bomb. (Use the matched set as approximation.)
    // Horizontal.
    for (var r = 0; r < _rows; r++) {
      var c = 0;
      while (c < _cols) {
        if (!matches.contains(r * _cols + c)) {
          c++;
          continue;
        }
        var k = c;
        while (k < _cols && matches.contains(r * _cols + k)) {
          k++;
        }
        final runLen = k - c;
        if (runLen >= 5) {
          final cc = (c + k) ~/ 2;
          _grid[r][cc] = _kBomb;
          _stripesCreated.add(r * _cols + cc);
        } else if (runLen >= 4) {
          final cc = (c + k) ~/ 2;
          // Vary orientation by row.
          _grid[r][cc] = (r.isEven) ? _kStripedH : _kStripedV;
          _stripesCreated.add(r * _cols + cc);
        }
        c = k;
      }
    }
    // Vertical.
    for (var c = 0; c < _cols; c++) {
      var r = 0;
      while (r < _rows) {
        if (!matches.contains(r * _cols + c)) {
          r++;
          continue;
        }
        var k = r;
        while (k < _rows && matches.contains(k * _cols + c)) {
          k++;
        }
        final runLen = k - r;
        if (runLen >= 5) {
          final rr = (r + k) ~/ 2;
          _grid[rr][c] = _kBomb;
          _stripesCreated.add(rr * _cols + c);
        } else if (runLen >= 4) {
          final rr = (r + k) ~/ 2;
          _grid[rr][c] = (c.isEven) ? _kStripedV : _kStripedH;
          _stripesCreated.add(rr * _cols + c);
        }
        r = k;
      }
    }
  }

  Future<void> _animateGravity() async {
    // Collect moves needed (per column: how far each cell drops).
    final drops = <_DropMove>[];
    for (var c = 0; c < _cols; c++) {
      var writeRow = _rows - 1;
      for (var r = _rows - 1; r >= 0; r--) {
        if (_grid[r][c] != _kEmpty) {
          if (writeRow != r) {
            drops.add(_DropMove(fromR: r, toR: writeRow, col: c));
          }
          writeRow--;
        }
      }
    }
    if (drops.isEmpty) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final completer = _Completer();
    ctrl.addListener(() {
      final t = Curves.easeOutCubic.transform(ctrl.value);
      setState(() {
        for (final m in drops) {
          final anim = _anims[m.fromR][m.col];
          anim.fallOffset = (m.toR - m.fromR) * _cellSize * t;
        }
      });
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        // Apply drops + reset fall offsets.
        setState(() {
          for (final m in drops) {
            final v = _grid[m.fromR][m.col];
            _grid[m.fromR][m.col] = _kEmpty;
            _grid[m.toR][m.col] = v;
            _anims[m.fromR][m.col].fallOffset = 0;
            _anims[m.toR][m.col].fallOffset = 0;
          }
        });
        ctrl.dispose();
        completer.complete();
      }
    });
    ctrl.forward();
    await completer.future;
  }

  void _refillBoard() {
    for (var c = 0; c < _cols; c++) {
      var emptyCount = 0;
      for (var r = 0; r < _rows; r++) {
        if (_grid[r][c] == _kEmpty) emptyCount++;
      }
      if (emptyCount == 0) continue;
      // Spawn new candies into the empty slots.
      for (var r = 0; r < _rows; r++) {
        if (_grid[r][c] == _kEmpty) {
          // Pull from queue.
          final color = _nextQueue.first;
          _nextQueue.removeAt(0);
          _nextQueue.add(_rng.nextInt(_level.colors));
          _grid[r][c] = color;
          // Mark a "spawn fall" animation offset.
          _anims[r][c].fallOffset = -(emptyCount) * _cellSize;
        }
      }
    }
    // Reset the spawn fall by animating them down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playSpawnFall();
    });
  }

  Future<void> _playSpawnFall() async {
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final completer = _Completer();
    ctrl.addListener(() {
      final t = Curves.easeOutCubic.transform(ctrl.value);
      setState(() {
        for (var r = 0; r < _rows; r++) {
          for (var c = 0; c < _cols; c++) {
            if (_anims[r][c].fallOffset < 0) {
              _anims[r][c].fallOffset *= (1 - t);
            }
          }
        }
      });
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {
          for (var r = 0; r < _rows; r++) {
            for (var c = 0; c < _cols; c++) {
              _anims[r][c].fallOffset = 0;
            }
          }
        });
        ctrl.dispose();
        completer.complete();
      }
    });
    ctrl.forward();
    await completer.future;
  }

  // ─────────────────────────────────────────────────────────────
  // Boosters
  // ─────────────────────────────────────────────────────────────────────────────

  void _useBomb() {
    if (_gameOver || _animating) return;
    if (_bombCharges <= 0) return;
    // Clear a 3x3 area around center.
    _bombCharges--;
    final r = _rows ~/ 2;
    final c = _cols ~/ 2;
    final toClear = <int>{};
    for (var rr = r - 1; rr <= r + 1; rr++) {
      for (var cc = c - 1; cc <= c + 1; cc++) {
        if (rr >= 0 && rr < _rows && cc >= 0 && cc < _cols) {
          toClear.add(rr * _cols + cc);
        }
      }
    }
    _matched
      ..clear()
      ..addAll(toClear);
    _resolveBoard().then((_) {
      _checkEnd();
      _animating = false;
    });
    _animating = true;
    haptic(HapticFeedbackType.heavy);
  }

  void _useShuffle() {
    if (_gameOver || _animating) return;
    if (_shuffleCharges <= 0) return;
    _shuffleCharges--;
    // Shuffle all non-empty cells.
    final cells = <int>[];
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (_grid[r][c] != _kEmpty) cells.add(_grid[r][c]);
      }
    }
    cells.shuffle(_rng);
    var idx = 0;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (_grid[r][c] != _kEmpty) {
          _grid[r][c] = cells[idx++];
        }
      }
    }
    setState(() {});
    haptic(HapticFeedbackType.medium);
  }

  void _useHint() {
    if (_gameOver || _animating) return;
    if (_hintCharges <= 0) return;
    _hintCharges--;
    _hintFlash = 1.0;
    haptic(HapticFeedbackType.selection);
  }

  // ─────────────────────────────────────────────────────────────
  // End conditions
  // ─────────────────────────────────────────────────────────────────────────────

  void _checkEnd() {
    if (_score >= _targetScore) {
      _gameOver = true;
      _won = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('You won! Score $_score');
      reportGameOver();
      return;
    }
    if (_movesLeft <= 0) {
      _gameOver = true;
      _won = false;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Out of moves — Score $_score');
      reportGameOver();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Tick loop — drive floaters, sparks, hint flash.
  // ─────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;
    var dirty = false;
    // Drive one final frame of VFX (sparks + floaters) after the game
    // has ended, then stop the ticker — otherwise it keeps repainting
    // under the host's game-over overlay and starves the UI ("freeze
    // mid-gameplay").
    if (_hintFlash > 0) {
      _hintFlash = max(0, _hintFlash - dt * 1.4);
      dirty = true;
    }
    for (final s in _sparks) {
      s.life -= dt * 1.4;
      s.x += s.vx * dt;
      s.y += s.vy * dt + 0.5 * 800 * dt * dt;
      s.vx *= 0.96;
      s.vy = s.vy * 0.96 + 240 * dt;
      dirty = true;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    for (final f in _floaters) {
      f.life -= dt;
      f.y -= 26 * dt;
      dirty = true;
    }
    _floaters.removeWhere((f) => f.life <= 0);
    if (dirty) setState(() {});
    if (_gameOver && _ticker.isActive) _ticker.stop();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _idleCtrl,
        builder: (context, _) {
          return _CandyDropScene(
            grid: _grid,
            anims: _anims,
            cols: _cols,
            rows: _rows,
            cellSize: _cellSize,
            boardLeft: _boardLeft,
            boardTop: _boardTop,
            palette: _kFlavors,
            idleT: _idleCtrl.value,
            selectedR: _selectedRow,
            selectedC: _selectedCol,
            matched: _matched,
            hintFlash: _hintFlash,
            sparks: _sparks,
            floaters: _floaters,
            nextQueue: _nextQueue,
            score: _score,
            target: _targetScore,
            movesLeft: _movesLeft,
            bombCharges: _bombCharges,
            shuffleCharges: _shuffleCharges,
            hintCharges: _hintCharges,
            gameOver: _gameOver,
            won: _won,
            onCellTap: (pos) => _onCellTap(pos.r, pos.c),
            onBomb: _useBomb,
            onShuffle: _useShuffle,
            onHint: _useHint,
            onLayout: (boardLeft, boardTop, cellSize) {
              _boardLeft = boardLeft;
              _boardTop = boardTop;
              _cellSize = cellSize;
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Cell animation state — small struct held per grid cell.
// ─────────────────────────────────────────────────────────────────────────────

class _CellAnim {
  Offset offset = Offset.zero; // for swap tween
  double scale = 1.0;
  double fallOffset = 0; // for gravity/spawn
  double flash = 0; // matched-candy glow (0..1)
}

class _DropMove {
  _DropMove({required this.fromR, required this.toR, required this.col});
  final int fromR;
  final int toR;
  final int col;
}

class _Spark {
  _Spark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.color,
    required this.size,
    required this.star,
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
  double size;
  bool star;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    required this.life,
  });
  double x;
  double y;
  String text;
  Color color;
  double life;
}

/// Tiny awaitable without importing dart:async.
class _Completer {
  final List<void Function()> _completers = [];
  Future<void> get future {
    if (_completers.isEmpty) {
      return Future<void>.value();
    }
    final c = _Completer();
    _completers.add(() => c._complete());
    return c.future;
  }

  void _complete() {}

  void complete() {
    for (final cb in _completers) {
      cb();
    }
    _completers.clear();
  }
}

// ─────────────────────────────────────────────────────────────────
// Scene widget — paints background, board, controls.
// ─────────────────────────────────────────────────────────────────────────────

class _CandyDropScene extends StatelessWidget {
  const _CandyDropScene({
    required this.grid,
    required this.anims,
    required this.cols,
    required this.rows,
    required this.cellSize,
    required this.boardLeft,
    required this.boardTop,
    required this.palette,
    required this.idleT,
    required this.selectedR,
    required this.selectedC,
    required this.matched,
    required this.hintFlash,
    required this.sparks,
    required this.floaters,
    required this.nextQueue,
    required this.score,
    required this.target,
    required this.movesLeft,
    required this.bombCharges,
    required this.shuffleCharges,
    required this.hintCharges,
    required this.gameOver,
    required this.won,
    required this.onCellTap,
    required this.onBomb,
    required this.onShuffle,
    required this.onHint,
    required this.onLayout,
  });

  final List<List<int>> grid;
  final List<List<_CellAnim>> anims;
  final int cols;
  final int rows;
  final double cellSize;
  final double boardLeft;
  final double boardTop;
  final List<_FlavorPalette> palette;
  final double idleT;
  final int? selectedR;
  final int? selectedC;
  final Set<int> matched;
  final double hintFlash;
  final List<_Spark> sparks;
  final List<_Floater> floaters;
  final List<int> nextQueue;
  final int score;
  final int target;
  final int movesLeft;
  final int bombCharges;
  final int shuffleCharges;
  final int hintCharges;
  final bool gameOver;
  final bool won;
  final ValueChanged<_Pos> onCellTap;
  final VoidCallback onBomb;
  final VoidCallback onShuffle;
  final VoidCallback onHint;
  final void Function(double left, double top, double cellSize) onLayout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFC8DC),
            Color(0xFFFF9CCC),
            Color(0xFFE0BBE4),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          // Reserve top 110dp for header, bottom 90dp for boosters.
          const topReserve = 110.0;
          const bottomReserve = 90.0;
          final boardAreaW = w - 16;
          final boardAreaH = h - topReserve - bottomReserve;
          final cs = (boardAreaW / cols).clamp(28.0, 56.0);
          final boardW = cs * cols;
          final boardH = cs * rows;
          final left = (w - boardW) / 2;
          final top = topReserve + (boardAreaH - boardH) / 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onLayout(left, top, cs);
          });

          return Stack(
            children: [
              // Background confetti pattern (light dots).
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BgPatternPainter(idleT: idleT),
                  ),
                ),
              ),
              // Header (Level + score + progress).
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _Header(
                  score: score,
                  target: target,
                  movesLeft: movesLeft,
                ),
              ),
              // Next queue preview.
              Positioned(
                left: 16,
                right: 16,
                top: 56,
                child: _NextQueue(
                  queue: nextQueue,
                  palette: palette,
                  cellSize: cs * 0.55,
                ),
              ),
              // Board + tap targets.
              Positioned(
                left: left,
                top: top,
                width: boardW,
                height: boardH,
                child: _Board(
                  grid: grid,
                  anims: anims,
                  cols: cols,
                  rows: rows,
                  cellSize: cs,
                  palette: palette,
                  idleT: idleT,
                  selectedR: selectedR,
                  selectedC: selectedC,
                  matched: matched,
                  hintFlash: hintFlash,
                  onCellTap: (r, col) => onCellTap(_Pos(r, col)),
                ),
              ),
              // Floaters and sparks overlays.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FxPainter(
                      sparks: sparks,
                      floaters: floaters,
                    ),
                  ),
                ),
              ),
              // Boosters.
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: _Boosters(
                  bombCharges: bombCharges,
                  shuffleCharges: shuffleCharges,
                  hintCharges: hintCharges,
                  onBomb: onBomb,
                  onShuffle: onShuffle,
                  onHint: onHint,
                ),
              ),
              // Game-over overlay.
              if (gameOver)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: won
                                ? const Color(0xFFFFD23F)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Text(
                            won ? 'Level Cleared!' : 'Out of Moves',
                            style: TextStyle(
                              color: won
                                  ? const Color(0xFF4A2E00)
                                  : const Color(0xFF1E3A8A),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Pos {
  const _Pos(this.r, this.c);
  final int r;
  final int c;
}

// ─────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.score,
    required this.target,
    required this.movesLeft,
  });
  final int score;
  final int target;
  final int movesLeft;

  @override
  Widget build(BuildContext context) {
    final progress = (score / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Moves chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded,
                    color: Color(0xFFFFB347), size: 18),
                const SizedBox(width: 2),
                Text(
                  '$movesLeft',
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Progress bar + score.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        color: Color(0xFF4A1860),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '$score / $target',
                      style: const TextStyle(
                        color: Color(0xFF4A1860),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.45),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF5BAA),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Next queue
// ─────────────────────────────────────────────────────────────────────────────

class _NextQueue extends StatelessWidget {
  const _NextQueue({
    required this.queue,
    required this.palette,
    required this.cellSize,
  });
  final List<int> queue;
  final List<_FlavorPalette> palette;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          'NEXT',
          style: TextStyle(
            color: Color(0xFF4A1860),
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        for (var i = 0; i < queue.length; i++) ...[
          Container(
            width: cellSize + 4,
            height: cellSize + 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(cellSize * 0.3),
              border: Border.all(
                color: Colors.white,
                width: 1.4,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CustomPaint(
                painter: _CandyPainter(
                  flavor: queue[i],
                  palette: palette,
                  scale: 1.0,
                  bob: i * 0.4,
                  matched: false,
                  timeMs: i * 200,
                ),
              ),
            ),
          ),
          if (i < queue.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Board widget — renders grid + tap targets.
// ─────────────────────────────────────────────────────────────────────────────

class _Board extends StatelessWidget {
  const _Board({
    required this.grid,
    required this.anims,
    required this.cols,
    required this.rows,
    required this.cellSize,
    required this.palette,
    required this.idleT,
    required this.selectedR,
    required this.selectedC,
    required this.matched,
    required this.hintFlash,
    required this.onCellTap,
  });
  final List<List<int>> grid;
  final List<List<_CellAnim>> anims;
  final int cols;
  final int rows;
  final double cellSize;
  final List<_FlavorPalette> palette;
  final double idleT;
  final int? selectedR;
  final int? selectedC;
  final Set<int> matched;
  final double hintFlash;
  final void Function(int r, int c) onCellTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // Board background.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(cellSize * 0.30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
            ),
          ),
          // Hint flash overlay (translucent white pulse).
          if (hintFlash > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18 * hintFlash),
                    borderRadius: BorderRadius.circular(cellSize * 0.30),
                  ),
                ),
              ),
            ),
          // Cells.
          for (var r = 0; r < rows; r++)
            for (var c = 0; c < cols; c++)
              Positioned(
                left: c * cellSize,
                top: r * cellSize,
                width: cellSize,
                height: cellSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onCellTap(r, c),
                  child: _CellLayer(
                    flavor: grid[r][c],
                    palette: palette,
                    cellSize: cellSize,
                    anim: anims[r][c],
                    isSelected: selectedR == r && selectedC == c,
                    isMatched: matched.contains(r * cols + c),
                    idleT: idleT,
                    row: r,
                    col: c,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Cell layer — wraps a CandyPainter and the swap/glow effects.
// ─────────────────────────────────────────────────────────────────────────────

class _CellLayer extends StatelessWidget {
  const _CellLayer({
    required this.flavor,
    required this.palette,
    required this.cellSize,
    required this.anim,
    required this.isSelected,
    required this.isMatched,
    required this.idleT,
    required this.row,
    required this.col,
  });
  final int flavor;
  final List<_FlavorPalette> palette;
  final double cellSize;
  final _CellAnim anim;
  final bool isSelected;
  final bool isMatched;
  final double idleT;
  final int row;
  final int col;

  @override
  Widget build(BuildContext context) {
    if (flavor == _kEmpty) return const SizedBox.shrink();
    final cs = cellSize;
    final bob = sin(idleT * 2 * pi + (row + col) * 0.6) * cs * 0.04;
    return RepaintBoundary(
      child: Transform.translate(
        offset: anim.offset + Offset(0, bob + anim.fallOffset),
        child: Transform.scale(
          scale: anim.scale,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(cs, cs),
                painter: _CandyPainter(
                  flavor: flavor,
                  palette: palette,
                  scale: 1.0,
                  bob: 0,
                  matched: isMatched,
                  timeMs: ((row * 31 + col * 17) % 1000),
                ),
              ),
              if (isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SelectionGlowPainter(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

class _BgPatternPainter extends CustomPainter {
  _BgPatternPainter({required this.idleT});
  final double idleT;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // Scattered candy dots.
    final dotP = Paint()
      ..color = Colors.white.withValues(alpha: 0.18);
    final dots = [
      [0.10, 0.18], [0.78, 0.20], [0.26, 0.74], [0.82, 0.66],
      [0.07, 0.50], [0.91, 0.36], [0.46, 0.10], [0.66, 0.92],
      [0.20, 0.36], [0.58, 0.30], [0.37, 0.62], [0.74, 0.85],
    ];
    for (final pt in dots) {
      final r = 1.6 + 0.6 * sin(idleT * 2 + pt[0] * 10);
      canvas.drawCircle(
        Offset(pt[0] * size.width, pt[1] * size.height),
        r,
        dotP,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BgPatternPainter old) =>
      old.idleT != idleT;
}

class _CandyPainter extends CustomPainter {
  _CandyPainter({
    required this.flavor,
    required this.palette,
    required this.scale,
    required this.bob,
    required this.matched,
    required this.timeMs,
  });
  final int flavor;
  final List<_FlavorPalette> palette;
  final double scale;
  final double bob;
  final bool matched;
  final int timeMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (flavor == _kEmpty) return;
    final w = size.width;
    final h = size.height;
    final r = (w * 0.42).clamp(8.0, 26.0);
    final c = Offset(w / 2, h / 2);
    // Soft drop shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + r * 0.7),
        width: r * 1.6,
        height: r * 0.45,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    if (flavor == _kStripedH) {
      _drawStriped(canvas, c, r, horizontal: true);
    } else if (flavor == _kStripedV) {
      _drawStriped(canvas, c, r, horizontal: false);
    } else if (flavor == _kBomb) {
      _drawBomb(canvas, c, r);
    } else {
      _drawRound(canvas, c, r, palette[flavor % palette.length]);
    }
    if (matched) {
      // Sparkle halo on match.
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  void _drawRound(Canvas canvas, Offset c, double r, _FlavorPalette p) {
    // Body — radial gradient.
    final gradientCenter = Alignment(
      (c.dx - r * 0.30 - c.dx) / r,
      (c.dy - r * 0.40 - c.dy) / r,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: gradientCenter,
          radius: r * 1.3,
          colors: [p.highlight, p.body],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Glossy crescent highlight.
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.36),
      r * 0.30,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    // Tiny kawaii eyes (just two dots — small).
    final eyeR = r * 0.08;
    final eyeDx = r * 0.18;
    canvas.drawCircle(
      c + Offset(-eyeDx, r * 0.05),
      eyeR,
      Paint()..color = const Color(0xFF1F0A14),
    );
    canvas.drawCircle(
      c + Offset(eyeDx, r * 0.05),
      eyeR,
      Paint()..color = const Color(0xFF1F0A14),
    );
  }

  void _drawStriped(Canvas canvas, Offset c, double r,
      {required bool horizontal}) {
    final p = palette[0];
    // Body.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            -0.30,
            -0.40,
          ),
          radius: r * 1.3,
          colors: [p.highlight, p.body],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Stripes (white).
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = r * 0.10
      ..strokeCap = StrokeCap.round;
    if (horizontal) {
      for (var i = -2; i <= 2; i++) {
        final dy = i * r * 0.32;
        canvas.drawLine(
          Offset(c.dx - r * 0.75, c.dy + dy),
          Offset(c.dx + r * 0.75, c.dy + dy),
          stripe,
        );
      }
    } else {
      for (var i = -2; i <= 2; i++) {
        final dx = i * r * 0.32;
        canvas.drawLine(
          Offset(c.dx + dx, c.dy - r * 0.75),
          Offset(c.dx + dx, c.dy + r * 0.75),
          stripe,
        );
      }
    }
    // Highlight.
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.36),
      r * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _drawBomb(Canvas canvas, Offset c, double r) {
    // Rainbow ring (alternating 6 flavor colors).
    final arcRect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < 6; i++) {
      final p = palette[i];
      final a0 = -pi / 2 + i * pi / 3;
      final a1 = a0 + pi / 3;
      final wedgePaint = Paint()..color = p.body;
      canvas.drawArc(arcRect, a0, a1 - a0, true, wedgePaint);
      canvas.drawArc(
        arcRect,
        a0,
        a1 - a0,
        true,
        Paint()
          ..color = p.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    // Centre sparkle.
    canvas.drawCircle(
      c,
      r * 0.30,
      Paint()..color = Colors.white,
    );
    _drawTinyStar(canvas, c + Offset(-r * 0.10, -r * 0.10), r * 0.10, Colors.white, 1);
  }

  void _drawTinyStar(Canvas canvas, Offset c, double s, Color color, double a) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final ang = -pi / 2 + i * pi / 4;
      final rad = i.isEven ? s : s * 0.4;
      final px = c.dx + cos(ang) * rad;
      final py = c.dy + sin(ang) * rad;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: a),
    );
  }

  @override
  bool shouldRepaint(covariant _CandyPainter old) =>
      old.flavor != flavor ||
      old.matched != matched ||
      old.timeMs != timeMs;
}

class _SelectionGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide * 0.46);
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFFFFD23F).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
    canvas.drawCircle(
      c,
      r + 3,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionGlowPainter old) => false;
}

class _FxPainter extends CustomPainter {
  _FxPainter({required this.sparks, required this.floaters});
  final List<_Spark> sparks;
  final List<_Floater> floaters;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparks) {
      final alpha = s.life.clamp(0.0, 1.0);
      if (s.star) {
        _drawStar(canvas, Offset(s.x, s.y), s.size, s.color, alpha);
      } else {
        canvas.drawCircle(
          Offset(s.x, s.y),
          s.size,
          Paint()..color = s.color.withValues(alpha: alpha),
        );
      }
    }
    for (final f in floaters) {
      final alpha = (f.life / 1.4).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            color: f.color.withValues(alpha: alpha),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(blurRadius: 4, color: Color(0x99000000)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(f.x - tp.width / 2, f.y));
    }
  }

  void _drawStar(Canvas canvas, Offset c, double s, Color color, double alpha) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final ang = -pi / 2 + i * pi / 4;
      final rad = i.isEven ? s : s * 0.4;
      final px = c.dx + cos(ang) * rad;
      final py = c.dy + sin(ang) * rad;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) =>
      old.sparks != sparks || old.floaters != floaters;
}

// ─────────────────────────────────────────────────────────────────
// Boosters
// ─────────────────────────────────────────────────────────────────────────────

class _Boosters extends StatelessWidget {
  const _Boosters({
    required this.bombCharges,
    required this.shuffleCharges,
    required this.hintCharges,
    required this.onBomb,
    required this.onShuffle,
    required this.onHint,
  });
  final int bombCharges;
  final int shuffleCharges;
  final int hintCharges;
  final VoidCallback onBomb;
  final VoidCallback onShuffle;
  final VoidCallback onHint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _BoosterButton(
          icon: Icons.bubble_chart_rounded,
          color: const Color(0xFFFF5BAA),
          charges: bombCharges,
          onTap: bombCharges > 0 ? onBomb : null,
        ),
        _BoosterButton(
          icon: Icons.shuffle_rounded,
          color: const Color(0xFF8B5CF6),
          charges: shuffleCharges,
          onTap: shuffleCharges > 0 ? onShuffle : null,
        ),
        _BoosterButton(
          icon: Icons.lightbulb_rounded,
          color: const Color(0xFFFFD23F),
          charges: hintCharges,
          onTap: hintCharges > 0 ? onHint : null,
        ),
      ],
    );
  }
}

class _BoosterButton extends StatelessWidget {
  const _BoosterButton({
    required this.icon,
    required this.color,
    required this.charges,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final int charges;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            if (charges > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$charges',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}