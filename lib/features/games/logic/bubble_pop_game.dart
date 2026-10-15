import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_widgets.dart';
import '../mini_game.dart';

/// **Bubble Shooter** — a faithful, canonical implementation of the
/// classic Puzzle Bobble / Bust-a-Move / Bubble Shooter game.
///
/// Layout (classic spec):
///   * 8 columns × 14 rows hex grid. Even rows have 8 bubbles (cols
///     0..7); odd rows have 7 bubbles (cols 1..7) shifted right by
///     half a cell width.
///   * Vertical row pitch = sqrt(3)/2 × bubble diameter.
///   * Bubble radius = cellWidth / 2 = bubble diameter / 2.
///
/// Gameplay loop:
///   * Aim by dragging from the bottom-center launcher.
///   * The projectile travels in a straight line, bouncing off the
///     left/right walls, until it touches a filled cell or the
///     ceiling.
///   * On collision, the projectile snaps to the empty hex neighbor
///     closest to its approach angle.
///   * If the snapped bubble forms a group of **3+ same-color
///     connected** bubbles, that group pops.
///   * After every pop, any bubbles no longer connected to the
///     ceiling row become **orphans** and fall (with bonus points).
///   * Every 5 shots, the ceiling pushes down by one row and a new
///     row of random bubbles is added at the top.
///   * Game ends when any bubble crosses the **danger line** (drawn
///     near the bottom of the play area).
///
/// Visuals:
///   * Glossy radial-gradient bubbles with white highlight crescent.
///   * Dashed trajectory preview with wall-bounce prediction.
///   * Rotating launcher cannon with current + next bubble indicators.
///   * Pop sparks, "COMBO!" floaters, falling-orphan animation.
class BubblePopGame extends MiniGame {
  const BubblePopGame({
    super.key,
    required super.callbacks,
    this.dailyChallenge = false,
  });

  final bool dailyChallenge;

  @override
  State<BubblePopGame> createState() => _BubblePopState();
}

// ─────────────────────────────────────────────────────────────────
// Board geometry — hex grid with offset rows.
// ─────────────────────────────────────────────────────────────────────────────

const int _kCols = 8;        // even rows have 8 cells
const int _kRows = 14;       // total logical rows
const int _kCeilingPushEvery = 5; // push ceiling down every N shots
const int _kStartRows = 5;   // initial filled rows
const int _kMatchMin = 3;    // minimum group size to pop

/// 6 hex-direction neighbor offsets per row parity.
const List<List<int>> _neighborsEven = [
  [-1, -1],
  [-1, 0],
  [0, -1],
  [0, 1],
  [1, -1],
  [1, 0],
];
const List<List<int>> _neighborsOdd = [
  [-1, 0],
  [-1, 1],
  [0, -1],
  [0, 1],
  [1, 0],
  [1, 1],
];

List<List<int>> _neighbors(int row) =>
    row.isEven ? _neighborsEven : _neighborsOdd;

/// Cell at (row, col) returns the index in the flat board array or
/// -1 if the cell is outside the offset geometry.
int _cellIdx(int row, int col) {
  if (row < 0 || row >= _kRows) return -1;
  // Even rows: cols 0..(_kCols-1); odd rows: cols 1..(_kCols-1) shifted.
  // To keep a flat 8-wide array, we pad odd rows so col 0 is unused.
  // For our logic, we store only valid cells and treat col < minCol as
  // "out of bounds" via the index check below.
  if (row.isEven) {
    if (col < 0 || col >= _kCols) return -1;
  } else {
    if (col < 1 || col >= _kCols) return -1;
  }
  return row * _kCols + col;
}

bool _isValidCell(int row, int col) {
  return _cellIdx(row, col) != -1;
}

// ─────────────────────────────────────────────────────────────────
// Color enum & palette
// ─────────────────────────────────────────────────────────────────────────────

enum _BubbleColor {
  red,
  blue,
  green,
  yellow,
  purple,
  orange,
}

class _ColorDef {
  const _ColorDef({
    required this.body,
    required this.highlight,
    required this.outline,
    required this.accent,
  });
  final Color body;
  final Color highlight;
  final Color outline;
  final Color accent;
}

const List<_ColorDef> _kPalette = [
  // red
  _ColorDef(
    body: Color(0xFFEF4444),
    highlight: Color(0xFFFF8B8B),
    outline: Color(0xFF7F1D1D),
    accent: Color(0xFFFFE0E0),
  ),
  // blue
  _ColorDef(
    body: Color(0xFF3B82F6),
    highlight: Color(0xFF93C5FD),
    outline: Color(0xFF1E3A8A),
    accent: Color(0xFFDBEAFE),
  ),
  // green
  _ColorDef(
    body: Color(0xFF22C55E),
    highlight: Color(0xFF86EFAC),
    outline: Color(0xFF14532D),
    accent: Color(0xFFDCFCE7),
  ),
  // yellow
  _ColorDef(
    body: Color(0xFFFACC15),
    highlight: Color(0xFFFDE68A),
    outline: Color(0xFF713F12),
    accent: Color(0xFFFEF9C3),
  ),
  // purple
  _ColorDef(
    body: Color(0xFFA855F7),
    highlight: Color(0xFFD8B4FE),
    outline: Color(0xFF581C87),
    accent: Color(0xFFF3E8FF),
  ),
  // orange
  _ColorDef(
    body: Color(0xFFFB923C),
    highlight: Color(0xFFFDBA74),
    outline: Color(0xFF7C2D12),
    accent: Color(0xFFFFEDD5),
  ),
];

/// Number of colors used per level. Soft ramp: levels 1..4 use 5
/// colors, level 5+ uses all 6.
int _colorsForLevel(int level) {
  return level >= 5 ? 6 : 5;
}

// ─────────────────────────────────────────────────────────────────
// Game state
// ─────────────────────────────────────────────────────────────────────────────

class _BubblePopState extends MiniGameState<BubblePopGame>
    with TickerProviderStateMixin {
  late final Random _rng;
  late int _colorCount;

  /// Flat board indexed by _cellIdx. -1 means empty.
  late List<int> _board;
  int _score = 0;
  final int _targetScore = 5000;
  int _shotsTaken = 0;

  _BubbleColor _currentShot = _BubbleColor.red;
  _BubbleColor _nextShot = _BubbleColor.red;

  /// Active projectile.
  _Flyer? _flyer;
  /// Predicted trajectory path (dotted preview).
  List<Offset> _aimPoints = const [];
  double _cannonAngle = -pi / 2; // pointing up
  Offset? _aimFrom;

  // FX.
  final List<_Spark> _sparks = [];
  final List<_Floater> _floaters = [];
  final List<_Fallen> _fallen = []; // orphan bubbles falling off-screen
  final List<_PushRowFx> _pushFxs = []; // ceiling push animation

  // Heuristics / status.
  bool _gameOver = false;
  bool _won = false;
  bool _showTutorial = true;
  bool _tutorialDismissed = false;
  double _idleTime = 0;
  double _tutorialElapsed = 0;
  double _heartsPulse = 0;

  // Per-frame.
  DateTime _last = DateTime.now();
  late final Ticker _ticker;

  // Layout.
  double _canvasW = 0;
  double _canvasH = 0;
  double _bubbleDiameter = 32;
  double _gridLeft = 0;
  double _gridTop = 0;
  double _dangerY = 0;

  // Cannon position (bottom center, slightly above the floor).
  Offset get _cannonCenter {
    return Offset(_canvasW / 2, _canvasH - 56);
  }

  @override
  void initState() {
    super.initState();
    _rng = widget.dailyChallenge ? Random(42) : Random();
    _colorCount = _colorsForLevel(1);
    _initBoard();
    _currentShot = _rngBubble();
    _nextShot = _rngBubble();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportScore(_score);
      reportStats('Shots $_shotsTaken  •  Target $_targetScore');
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Board setup
  // ─────────────────────────────────────────────────────────────

  void _initBoard() {
    _board = List.filled(_kRows * _kCols, -1, growable: false);
    for (var r = 0; r < _kStartRows; r++) {
      for (var c = 0; c < _kCols; c++) {
        if (!_isValidCell(r, c)) continue;
        final idx = _cellIdx(r, c);
        _board[idx] = _rng.nextInt(_colorCount);
      }
    }
  }

  _BubbleColor _rngBubble() {
    return _BubbleColor.values[_rng.nextInt(_colorCount)];
  }

  // ─────────────────────────────────────────────────────────────
  // Layout helpers — convert between (row, col) and pixel center.
  // ─────────────────────────────────────────────────────────────

  /// Returns the pixel center of cell (row, col) or null if invalid.
  Offset? _cellCenterOrNull(int row, int col) {
    if (!_isValidCell(row, col)) return null;
    final r = _bubbleDiameter / 2;
    final dx = row.isOdd ? r : 0.0;
    final rowPitch = _bubbleDiameter * 0.866; // sqrt(3)/2
    return Offset(
      _gridLeft + col * _bubbleDiameter + r + dx,
      _gridTop + row * rowPitch + r,
    );
  }

  Offset _cellCenter(int row, int col) {
    return _cellCenterOrNull(row, col) ??
        Offset(_gridLeft, _gridTop); // fallback (shouldn't happen)
  }

  /// Inverse of _cellCenter: which (row, col) is the pixel closest to?
  (int, int) _pixelToCell(Offset p) {
    final r = _bubbleDiameter / 2;
    final rowPitch = _bubbleDiameter * 0.866;
    var row = ((p.dy - _gridTop - r) / rowPitch).round();
    if (row < 0) row = 0;
    if (row >= _kRows) row = _kRows - 1;
    final dx = row.isOdd ? r : 0.0;
    var col = ((p.dx - _gridLeft - r - dx) / _bubbleDiameter).round();
    if (col < 0) col = 0;
    if (col >= _kCols) col = _kCols - 1;
    return (row, col);
  }

  // ─────────────────────────────────────────────────────────────
  // Hex-neighbor iteration helpers
  // ─────────────────────────────────────────────────────────────

  /// Returns 6 valid neighbor (row, col) pairs of (row, col) that are
  /// inside the board AND inside the offset geometry.
  List<(int, int)> _hexNeighbors(int row, int col) {
    final out = <(int, int)>[];
    for (final d in _neighbors(row)) {
      final nr = row + d[0];
      final nc = col + d[1];
      if (_isValidCell(nr, nc)) out.add((nr, nc));
    }
    return out;
  }

  int _colorAt(int row, int col) {
    if (!_isValidCell(row, col)) return -1;
    return _board[_cellIdx(row, col)];
  }

  // ─────────────────────────────────────────────────────────────
  // Snap logic — given projectile position, find the empty cell to
  // snap into next to the bubble it collided with.
  // ─────────────────────────────────────────────────────────────

  /// Find the empty hex cell the projectile should snap into. Returns
  /// null if no collision yet.
  ///
  /// Algorithm:
  ///   1. For each filled cell, compute its center.
  ///   2. If projectile-to-center distance <= diameter, it's a hit.
  ///   3. Snap target = empty neighbor closest to the projectile
  ///      center.
  (int, int)? _findSnapCell(Offset pos) {
    final r = _bubbleDiameter / 2;
    var bestHitIdx = -1;
    var bestHitDist = r * 2.0 + 0.5; // a bit of tolerance
    for (var row = 0; row < _kRows; row++) {
      for (var col = 0; col < _kCols; col++) {
        if (_colorAt(row, col) == -1) continue;
        final center = _cellCenter(row, col);
        final d = (center - pos).distance;
        if (d < bestHitDist) {
          bestHitDist = d;
          bestHitIdx = _cellIdx(row, col);
        }
      }
    }
    if (bestHitIdx == -1) return null;
    final hitRow = bestHitIdx ~/ _kCols;
    final hitCol = bestHitIdx % _kCols;

    // Find the empty neighbor closest to the projectile.
    int bestIdx = -1;
    var bestD = double.infinity;
    for (final n in _hexNeighbors(hitRow, hitCol)) {
      if (_colorAt(n.$1, n.$2) != -1) continue;
      final center = _cellCenter(n.$1, n.$2);
      final d = (center - pos).distance;
      if (d < bestD) {
        bestD = d;
        bestIdx = _cellIdx(n.$1, n.$2);
      }
    }
    if (bestIdx == -1) {
      // Shouldn't happen if hit cell has any empty neighbor, but
      // fallback: search nearby empty cells.
      for (var row = 0; row < _kRows; row++) {
        for (var col = 0; col < _kCols; col++) {
          if (_colorAt(row, col) != -1) continue;
          final center = _cellCenter(row, col);
          final d = (center - pos).distance;
          if (d < bestD) {
            bestD = d;
            bestIdx = _cellIdx(row, col);
          }
        }
      }
    }
    if (bestIdx == -1) return null;
    return (bestIdx ~/ _kCols, bestIdx % _kCols);
  }

  // ─────────────────────────────────────────────────────────────
  // Match-3 detection (flood-fill same color from cell)
  // ─────────────────────────────────────────────────────────────

  Set<int> _findCluster(int startRow, int startCol) {
    final color = _colorAt(startRow, startCol);
    if (color == -1) return <int>{};
    final visited = <int>{};
    final stack = <int>[_cellIdx(startRow, startCol)];
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      if (visited.contains(idx)) continue;
      if (_board[idx] != color) continue;
      visited.add(idx);
      final row = idx ~/ _kCols;
      final col = idx % _kCols;
      for (final n in _hexNeighbors(row, col)) {
        final nIdx = _cellIdx(n.$1, n.$2);
        if (visited.contains(nIdx)) continue;
        if (_board[nIdx] == color) stack.add(nIdx);
      }
    }
    return visited;
  }

  // ─────────────────────────────────────────────────────────────
  // Orphan detection — flood-fill ANY color from the ceiling row.
  // ─────────────────────────────────────────────────────────────

  Set<int> _connectedToCeiling() {
    final connected = <int>{};
    final stack = <int>[];
    for (var c = 0; c < _kCols; c++) {
      if (!_isValidCell(0, c)) continue;
      if (_colorAt(0, c) != -1) {
        stack.add(_cellIdx(0, c));
      }
    }
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      if (connected.contains(idx)) continue;
      if (_board[idx] == -1) continue;
      connected.add(idx);
      final row = idx ~/ _kCols;
      final col = idx % _kCols;
      for (final n in _hexNeighbors(row, col)) {
        final nIdx = _cellIdx(n.$1, n.$2);
        if (connected.contains(nIdx)) continue;
        if (_board[nIdx] != -1) stack.add(nIdx);
      }
    }
    return connected;
  }

  // ─────────────────────────────────────────────────────────────
  // Shot resolution
  // ─────────────────────────────────────────────────────────────

  void _resolveShot(int row, int col) {
    if (!_isValidCell(row, col)) return;
    if (_colorAt(row, col) != -1) return;
    setState(() {
      _board[_cellIdx(row, col)] = _currentShot.index;
      _shotsTaken++;
    });

    // 1. Pop same-color cluster if >= 3.
    final cluster = _findCluster(row, col);
    var gained = 0;
    if (cluster.length >= _kMatchMin) {
      for (final idx in cluster) {
        _board[idx] = -1;
      }
      gained += cluster.length * 10;
      _spawnPopFx(row, col, _currentShot, false);
      _floaterAt(row, col, '+${cluster.length * 10}',
          const Color(0xFFFFD23F));
      _bumpCombo(cluster.length);
      haptic(HapticFeedbackType.medium);
    }

    // 2. Drop orphans.
    final connected = _connectedToCeiling();
    var orphans = 0;
    for (var r = 0; r < _kRows; r++) {
      for (var c = 0; c < _kCols; c++) {
        final idx = _cellIdx(r, c);
        if (idx == -1) continue;
        if (_board[idx] == -1) continue;
        if (!connected.contains(idx)) {
          // Convert to a falling bubble.
          _fallen.add(_Fallen(
            colorIdx: _board[idx],
            row: r,
            col: c,
            x: _cellCenter(r, c).dx,
            y: _cellCenter(r, c).dy,
            vy: 0,
          ));
          _board[idx] = -1;
          orphans++;
        }
      }
    }
    if (orphans > 0) {
      gained += orphans * 15;
      _floaterAt(row, col, '$orphans DROPS!', const Color(0xFFFF5BAA));
      haptic(HapticFeedbackType.heavy);
    }

    // 3. After-pop chain: look for new clusters formed by drops.
    var chainGained = 0;
    var chainRun = true;
    while (chainRun) {
      chainRun = false;
      for (var r = 0; r < _kRows; r++) {
        for (var c = 0; c < _kCols; c++) {
          if (_colorAt(r, c) == -1) continue;
          final cl = _findCluster(r, c);
          if (cl.length >= _kMatchMin) {
            for (final idx in cl) {
              _board[idx] = -1;
            }
            chainGained += cl.length * 10 * 2;
            _spawnPopFx(r, c, _BubbleColor.values[_colorAt(r, c)],
                true);
            _floaterAt(r, c, 'CHAIN! +${cl.length * 20}',
                const Color(0xFFFF5BAA));
            chainRun = true;
          }
        }
      }
      if (chainRun) {
        // Drop new orphans from chain pops.
        final c2 = _connectedToCeiling();
        for (var r = 0; r < _kRows; r++) {
          for (var c = 0; c < _kCols; c++) {
            final idx = _cellIdx(r, c);
            if (idx == -1) continue;
            if (_board[idx] == -1) continue;
            if (!c2.contains(idx)) {
              _board[idx] = -1;
            }
          }
        }
      }
    }
    gained += chainGained;

    setState(() {
      _score += gained;
    });
    reportScore(_score);
    reportStats('Shots $_shotsTaken  •  Target $_targetScore');

    // 4. Ceiling push every N shots.
    if (_shotsTaken % _kCeilingPushEvery == 0) {
      _pushCeiling();
    }

    // 5. Win/lose check.
    _checkStatus();

    // 6. Advance to next shot.
    if (!_gameOver) {
      _currentShot = _nextShot;
      _nextShot = _rngBubble();
    }
  }

  void _pushCeiling() {
    // Shift everything down by one row. The topmost row (row 0) is
    // filled with new random bubbles.
    final newBoard = List.filled(_kRows * _kCols, -1, growable: false);
    for (var r = 1; r < _kRows; r++) {
      for (var c = 0; c < _kCols; c++) {
        if (!_isValidCell(r, c)) continue;
        final fromIdx = _cellIdx(r, c);
        final toRow = r - 1;
        if (!_isValidCell(toRow, c)) continue;
        newBoard[_cellIdx(toRow, c)] = _board[fromIdx];
      }
    }
    // Fill row (_kRows - 1) with new random colors.
    for (var c = 0; c < _kCols; c++) {
      if (!_isValidCell(_kRows - 1, c)) continue;
      newBoard[_cellIdx(_kRows - 1, c)] = _rng.nextInt(_colorCount);
    }
    _board = newBoard;
    _pushFxs.add(_PushRowFx(life: 1.0));
    haptic(HapticFeedbackType.heavy);
  }

  int _combo = 0;
  void _bumpCombo(int n) {
    _combo++;
    if (_combo >= 2) {
      _floaterAt(2, 4, 'COMBO x$_combo!', const Color(0xFFFFD23F));
    }
  }

  void _floaterAt(int row, int col, String text, Color color) {
    final c = _cellCenter(row, col);
    _floaters.add(_Floater(
      x: c.dx,
      y: c.dy,
      text: text,
      color: color,
    ));
  }

  void _spawnPopFx(int row, int col, _BubbleColor color, bool small) {
    final c = _cellCenter(row, col);
    final n = small ? 6 : 12;
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final sp = 80 + _rng.nextDouble() * 100;
      _sparks.add(_Spark(
        x: c.dx,
        y: c.dy,
        vx: cos(a) * sp,
        vy: sin(a) * sp - 30,
        life: small ? 0.6 : 0.9,
        color: _kPalette[color.index].body,
        size: 2.5 + _rng.nextDouble() * 2,
      ));
    }
  }

  void _checkStatus() {
    // Win.
    if (_score >= _targetScore) {
      _gameOver = true;
      _won = true;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('You won! Score $_score');
      reportGameOver();
      return;
    }
    // Lose: any bubble crosses the danger line.
    for (var r = 0; r < _kRows; r++) {
      for (var c = 0; c < _kCols; c++) {
        if (_colorAt(r, c) == -1) continue;
        if (!_isValidCell(r, c)) continue;
        // Convert row to pixel y.
        final y = _cellCenter(r, c).dy + _bubbleDiameter / 2;
        if (y >= _dangerY) {
          _gameOver = true;
          _won = false;
          _heartsPulse = 1.0;
          haptic(HapticFeedbackType.heavy);
          reportScore(_score);
          reportStats('Game over — Score $_score');
          reportGameOver();
          return;
        }
      }
    }
    // Soft loss (very long games).
    if (_shotsTaken > 80) {
      _gameOver = true;
      _won = false;
      haptic(HapticFeedbackType.heavy);
      reportScore(_score);
      reportStats('Out of shots — Score $_score');
      reportGameOver();
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (_gameOver) return;
    if (_flyer != null) return;
    _dismissTutorial();
    _updateAim(d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_gameOver) return;
    if (_flyer != null) return;
    _updateAim(d.localPosition);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_gameOver) return;
    if (_flyer != null) return;
    if (_aimFrom == null) return;
    _fire();
  }

  void _updateAim(Offset target) {
    final dir = target - _cannonCenter;
    // Clamp to upper hemisphere (allow slight downward bounce).
    final a = atan2(dir.dy, dir.dx);
    final clamped = a.clamp(-pi + 0.15, -0.15);
    setState(() {
      _aimFrom = target;
      _cannonAngle = clamped;
      _aimPoints = _predictTrajectory(_cannonCenter, clamped);
    });
  }

  void _fire() {
    final vel = Offset(cos(_cannonAngle) * 700, sin(_cannonAngle) * 700);
    final tip = _cannonCenter +
        Offset(cos(_cannonAngle), sin(_cannonAngle)) * 32;
    setState(() {
      _flyer = _Flyer(pos: tip, vel: vel);
      _aimPoints = const [];
      _aimFrom = null;
    });
  }

  /// Predict where the projectile will travel (and bounce). Used for
  /// the dotted trajectory preview.
  List<Offset> _predictTrajectory(Offset from, double angle) {
    final pts = <Offset>[from];
    var p = from;
    var v = Offset(cos(angle) * 700, sin(angle) * 700);
    final r = _bubbleDiameter / 2;
    var steps = 0;
    while (steps < 200) {
      p = p + v * 0.04;
      // Wall bounce.
      if (p.dx < r) {
        p = Offset(r, p.dy);
        v = Offset(-v.dx, v.dy);
      } else if (p.dx > _canvasW - r) {
        p = Offset(_canvasW - r, p.dy);
        v = Offset(-v.dx, v.dy);
      }
      pts.add(p);
      // Hit ceiling.
      if (p.dy < _gridTop + r) {
        // Snap into row 0.
        final snap = _findSnapCell(Offset(p.dx, _gridTop + r));
        if (snap != null) {
          pts.add(_cellCenter(snap.$1, snap.$2));
        }
        break;
      }
      // Hit existing bubble.
      final snap = _findSnapCell(p);
      if (snap != null) {
        pts.add(_cellCenter(snap.$1, snap.$2));
        break;
      }
      steps++;
    }
    return pts;
  }

  // ─────────────────────────────────────────────────────────────
  // Tick
  // ─────────────────────────────────────────────────────────────

  void _onTick(Duration _) {
    if (!mounted) return;
    final now = DateTime.now();
    var dt = now.difference(_last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    _idleTime += dt;
    _tutorialElapsed += dt;
    if (_showTutorial && _tutorialElapsed >= 6.0) {
      _showTutorial = false;
    }
    var dirty = false;

    // Hearts pulse.
    if (_heartsPulse > 0) {
      _heartsPulse = max(0, _heartsPulse - dt * 2.0);
      dirty = true;
    }

    // Push FX.
    if (_pushFxs.isNotEmpty) {
      for (final fx in _pushFxs) {
        fx.life -= dt;
      }
      _pushFxs.removeWhere((f) => f.life <= 0);
      dirty = true;
    }

    // Spark lifecycle.
    if (_sparks.isNotEmpty) {
      for (final s in _sparks) {
        s.life -= dt;
        s.x += s.vx * dt;
        s.y += s.vy * dt;
      }
      _sparks.removeWhere((s) => s.life <= 0);
      dirty = true;
    }

    // Floater lifecycle.
    if (_floaters.isNotEmpty) {
      for (final f in _floaters) {
        f.life -= dt;
        f.y -= 36 * dt;
      }
      _floaters.removeWhere((f) => f.life <= 0);
      dirty = true;
    }

    // Fallen orphans: integrate gravity until they fall off-screen.
    if (_fallen.isNotEmpty) {
      for (final b in _fallen) {
        b.vy += 600 * dt;
        b.y += b.vy * dt;
      }
      _fallen.removeWhere((b) => b.y > _canvasH + 60);
      dirty = true;
    }

    // Flyer physics.
    if (_flyer != null) {
      final f = _flyer!;
      f.pos = f.pos + f.vel * dt;
      final r = _bubbleDiameter / 2;
      // Wall bounce.
      if (f.pos.dx < r) {
        f.pos = Offset(r, f.pos.dy);
        f.vel = Offset(-f.vel.dx, f.vel.dy);
      } else if (f.pos.dx > _canvasW - r) {
        f.pos = Offset(_canvasW - r, f.pos.dy);
        f.vel = Offset(-f.vel.dx, f.vel.dy);
      }
      // Ceiling snap.
      if (f.pos.dy <= _gridTop + r) {
        final p = Offset(f.pos.dx, _gridTop + r);
        final snap = _findSnapCell(p);
        if (snap != null) {
          _resolveShot(snap.$1, snap.$2);
        } else {
          // Snap into row 0 at the nearest column.
          final (_, col) = _pixelToCell(p);
          final clampedCol = col.clamp(0, _kCols - 1);
          _resolveShot(0, clampedCol);
        }
        setState(() {
          _flyer = null;
        });
        _combo = 0;
        dirty = true;
      } else {
        // Collision against existing bubbles.
        final snap = _findSnapCell(f.pos);
        if (snap != null) {
          _resolveShot(snap.$1, snap.$2);
          setState(() {
            _flyer = null;
          });
          _combo = 0;
          dirty = true;
        }
      }
    }

    if (dirty) setState(() {});
  }

  void _dismissTutorial() {
    if (!_tutorialDismissed) {
      _tutorialDismissed = true;
      _showTutorial = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _canvasW = c.maxWidth;
        _canvasH = c.maxHeight;
        // Fit 8 columns + odd-row offset into the canvas with margin.
        final maxByW = (_canvasW - 24) / (_kCols + 0.5);
        _bubbleDiameter = maxByW.clamp(20.0, 44.0);
        _gridLeft = (_canvasW -
                (_kCols * _bubbleDiameter + _bubbleDiameter / 2)) /
            2;
        _gridTop = 90;
        _dangerY = _canvasH - 110;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Game painter.
            Positioned.fill(
              child: CustomPaint(
                painter: _BubbleShooterPainter(
                  board: _board,
                  bubbleDiameter: _bubbleDiameter,
                  gridLeft: _gridLeft,
                  gridTop: _gridTop,
                  canvasW: _canvasW,
                  canvasH: _canvasH,
                  dangerY: _dangerY,
                  cannonCenter: _cannonCenter,
                  cannonAngle: _cannonAngle,
                  currentShot: _currentShot,
                  nextShot: _nextShot,
                  flyer: _flyer,
                  aimPoints: _aimPoints,
                  sparks: _sparks,
                  floaters: _floaters,
                  fallen: _fallen,
                  pushFxs: _pushFxs,
                  idleTime: _idleTime,
                  gameOver: _gameOver,
                  won: _won,
                ),
              ),
            ),
            // Aim/drag surface.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
            ),
            if (_showTutorial)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: _TutorialOverlay(
                    elapsed: _tutorialElapsed,
                    onDismiss: _dismissTutorial,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Bubble entity, FX records
// ─────────────────────────────────────────────────────────────────────────────

class _Flyer {
  _Flyer({required this.pos, required this.vel});
  Offset pos;
  Offset vel;
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
  });
  double x;
  double y;
  double vx;
  double vy;
  double life;
  Color color;
  double size;
}

class _Floater {
  _Floater({
    required this.x,
    required this.y,
    required this.text,
    required this.color,
  }) : life = 1.4;
  double x;
  double y;
  String text;
  Color color;
  double life;
}

class _Fallen {
  _Fallen({
    required this.colorIdx,
    required this.row,
    required this.col,
    required this.x,
    required this.y,
    required this.vy,
  });
  int colorIdx;
  int row;
  int col;
  double x;
  double y;
  double vy;
}

class _PushRowFx {
  _PushRowFx({required this.life});
  double life;
}

// ─────────────────────────────────────────────────────────────────
// Tutorial overlay
// ─────────────────────────────────────────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  const _TutorialOverlay({
    required this.elapsed,
    required this.onDismiss,
  });
  final double elapsed;
  final VoidCallback onDismiss;

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _tk;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _tk = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    setState(() => _t += 1 / 60);
  }

  @override
  void dispose() {
    _tk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Curves.easeOutCubic.transform((_t * 3.5).clamp(0.0, 1.0));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + (1 - slide) * 60),
      child: Opacity(
        opacity: slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded,
                  color: Color(0xFF1E3A8A), size: 28),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Drag to aim, release to shoot!',
                  style: TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0.2,
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
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _BubbleShooterPainter extends CustomPainter {
  _BubbleShooterPainter({
    required this.board,
    required this.bubbleDiameter,
    required this.gridLeft,
    required this.gridTop,
    required this.canvasW,
    required this.canvasH,
    required this.dangerY,
    required this.cannonCenter,
    required this.cannonAngle,
    required this.currentShot,
    required this.nextShot,
    required this.flyer,
    required this.aimPoints,
    required this.sparks,
    required this.floaters,
    required this.fallen,
    required this.pushFxs,
    required this.idleTime,
    required this.gameOver,
    required this.won,
  });

  final List<int> board;
  final double bubbleDiameter;
  final double gridLeft;
  final double gridTop;
  final double canvasW;
  final double canvasH;
  final double dangerY;
  final Offset cannonCenter;
  final double cannonAngle;
  final _BubbleColor currentShot;
  final _BubbleColor nextShot;
  final _Flyer? flyer;
  final List<Offset> aimPoints;
  final List<_Spark> sparks;
  final List<_Floater> floaters;
  final List<_Fallen> fallen;
  final List<_PushRowFx> pushFxs;
  final double idleTime;
  final bool gameOver;
  final bool won;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawDangerLine(canvas);
    _drawCeilingIndicator(canvas);
    _drawBubbles(canvas);
    _drawPushFx(canvas);
    _drawFallen(canvas);
    _drawAimTrajectory(canvas);
    _drawCannon(canvas);
    _drawFlyer(canvas);
    _drawSparks(canvas);
    _drawFloaters(canvas);
    if (gameOver) _drawGameOver(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0B1B3A),
          Color(0xFF1E2A78),
          Color(0xFF3D2A8C),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    // Subtle starfield.
    final rng = Random(7);
    for (var i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.5 + rng.nextDouble() * 1.5;
      final a = 0.2 + 0.4 * (sin(idleTime * 2 + i) + 1) * 0.5;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
  }

  void _drawDangerLine(Canvas canvas) {
    final p = Paint()
      ..color = const Color(0xFFFF3B5C).withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashW = 10.0;
    const gap = 6.0;
    var x = 0.0;
    while (x < canvasW) {
      canvas.drawLine(Offset(x, dangerY), Offset(x + dashW, dangerY), p);
      x += dashW + gap;
    }
    // Label.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'DANGER',
        style: TextStyle(
          color: Color(0xFFFF3B5C),
          fontWeight: FontWeight.w900,
          fontSize: 9,
          letterSpacing: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, dangerY - 14));
  }

  void _drawCeilingIndicator(Canvas canvas) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, gridTop - 4), Offset(canvasW, gridTop - 4), p);
  }

  void _drawBubbles(Canvas canvas) {
    for (var r = 0; r < _kRows; r++) {
      for (var c = 0; c < _kCols; c++) {
        final idx = r * _kCols + c;
        final v = board[idx];
        if (v == -1) continue;
        // Skip invalid offset cells (e.g. col 0 of odd rows).
        if (!_isValidCell(r, c)) continue;
        _drawBubble(
          canvas,
          _cellPx(r, c),
          bubbleDiameter / 2,
          _kPalette[v],
        );
      }
    }
  }

  Offset _cellPx(int row, int col) {
    final r = bubbleDiameter / 2;
    final dx = row.isOdd ? r : 0.0;
    final rowPitch = bubbleDiameter * 0.866;
    return Offset(
      gridLeft + col * bubbleDiameter + r + dx,
      gridTop + row * rowPitch + r,
    );
  }

  void _drawBubble(
    Canvas canvas,
    Offset c,
    double r,
    _ColorDef p,
  ) {
    // Drop shadow.
    canvas.drawCircle(
      Offset(c.dx, c.dy + r * 0.45),
      r * 1.05,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Body.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.30, -0.40),
          radius: 1.0,
          colors: [p.highlight, p.body],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Outline.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = p.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // Glossy crescent.
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.38),
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _drawPushFx(Canvas canvas) {
    for (final fx in pushFxs) {
      final t = (1 - fx.life).clamp(0.0, 1.0);
      final alpha = fx.life.clamp(0.0, 1.0);
      final yOff = (1 - t) * 8;
      canvas.drawRect(
        Rect.fromLTWH(0, gridTop - 8 - yOff, canvasW, 6),
        Paint()
          ..color = const Color(0xFFFFD23F).withValues(alpha: alpha * 0.6),
      );
    }
  }

  void _drawFallen(Canvas canvas) {
    for (final f in fallen) {
      _drawBubble(
        canvas,
        Offset(f.x, f.y),
        bubbleDiameter / 2,
        _kPalette[f.colorIdx],
      );
    }
  }

  void _drawAimTrajectory(Canvas canvas) {
    if (aimPoints.length < 2) return;
    final path = Path()..moveTo(aimPoints.first.dx, aimPoints.first.dy);
    for (var i = 1; i < aimPoints.length; i++) {
      path.lineTo(aimPoints[i].dx, aimPoints[i].dy);
    }
    // Outer glow.
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final extract = metric.extractPath(
          dist,
          (dist + 14).clamp(0, metric.length),
        );
        canvas.drawPath(
          extract,
          Paint()
            ..color = const Color(0xFF22D3EE).withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        dist += 22;
      }
    }
    // Bright dashes.
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final extract = metric.extractPath(
          dist,
          (dist + 10).clamp(0, metric.length),
        );
        canvas.drawPath(
          extract,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
        dist += 16;
      }
    }
  }

  void _drawCannon(Canvas canvas) {
    final cx = cannonCenter.dx;
    final cy = cannonCenter.dy;
    // Base.
    canvas.drawCircle(
      Offset(cx, cy + 22),
      24,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF1E1B4B)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy + 22), radius: 24)),
    );
    canvas.drawCircle(
      Offset(cx, cy + 22),
      24,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Barrel rotating with angle.
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(cannonAngle + pi / 2);
    final barrel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-7, -28, 14, 36),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      barrel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF312E81)],
        ).createShader(Rect.fromLTWH(-7, -28, 14, 36)),
    );
    canvas.drawRRect(
      barrel,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();

    // Loaded bubble at barrel tip.
    final tip = Offset(
      cx + cos(cannonAngle) * 32,
      cy + sin(cannonAngle) * 32,
    );
    _drawBubble(
      canvas,
      tip,
      bubbleDiameter / 2 * 0.85,
      _kPalette[currentShot.index],
    );

    // Next bubble indicator (small bubble above the cannon).
    final nextPos = Offset(cx + 32, cy + 6);
    canvas.drawCircle(
      nextPos,
      13,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    _drawBubble(
      canvas,
      nextPos,
      11,
      _kPalette[nextShot.index],
    );
    // "NEXT" label.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'NEXT',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 8,
          letterSpacing: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx + 46, cy + 2));
  }

  void _drawFlyer(Canvas canvas) {
    final f = flyer;
    if (f == null) return;
    _drawBubble(
      canvas,
      f.pos,
      bubbleDiameter / 2,
      _kPalette[currentShot.index],
    );
  }

  void _drawSparks(Canvas canvas) {
    for (final s in sparks) {
      final alpha = s.life.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(s.x, s.y),
        s.size,
        Paint()..color = s.color.withValues(alpha: alpha),
      );
    }
  }

  void _drawFloaters(Canvas canvas) {
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

  void _drawGameOver(Canvas canvas) {
    final overlay = Paint()
      ..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(Offset.zero & Size(canvasW, canvasH), overlay);
    final color = won ? const Color(0xFFFFD23F) : Colors.white;
    final text = won ? 'Level Cleared!' : 'Game Over';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(blurRadius: 8, color: Colors.black87),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(canvasW / 2 - tp.width / 2, canvasH / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleShooterPainter old) =>
      old.board != board ||
      old.bubbleDiameter != bubbleDiameter ||
      old.gridLeft != gridLeft ||
      old.gridTop != gridTop ||
      old.dangerY != dangerY ||
      old.cannonAngle != cannonAngle ||
      old.currentShot != currentShot ||
      old.nextShot != nextShot ||
      old.flyer != flyer ||
      old.aimPoints != aimPoints ||
      old.sparks != sparks ||
      old.floaters != floaters ||
      old.fallen != fallen ||
      old.pushFxs != pushFxs ||
      old.idleTime != idleTime ||
      old.gameOver != gameOver;
}