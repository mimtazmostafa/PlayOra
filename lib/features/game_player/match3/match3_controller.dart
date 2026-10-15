import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'match3_state.dart';

/// State of a single gem in the current animation frame.
class GemCell {
  GemCell({
    required this.type,
    required this.targetRow,
    required this.targetCol,
    Offset? offset,
    this.scale = 1.0,
    this.alpha = 1.0,
    this.highlighted = false,
    this.selected = false,
  }) : offset = offset ?? Offset.zero;

  GemType type;

  /// Final resting position (row, col) on the grid.
  int targetRow;
  int targetCol;

  /// Visual offset from the resting position, in logical pixels.
  /// Used by swap + drop animations.
  Offset offset;

  /// Scale factor 0..1. Drops to 0 when a gem is cleared (then the
  /// controller removes it from the list entirely).
  double scale;
  double alpha;

  /// True while the gem is the first tap of a potential swap.
  bool selected;

  /// True for a brief flash before clearing.
  bool highlighted;
}

/// A single particle puff that flies off a cleared gem.
class GemParticle {
  GemParticle({
    required this.color,
    required this.position,
    required this.velocity,
    required this.lifeMs,
    required this.totalLifeMs,
    required this.size,
  });

  final Color color;
  Offset position;
  Offset velocity;
  final double size;
  final int lifeMs;
  final int totalLifeMs;

  bool get isAlive => lifeMs > 0;
  double get progress => 1 - (lifeMs / totalLifeMs);
}

/// Top-level controller for the Match-3 game.
///
/// Owns:
///   - the [Match3Logic] (pure game engine)
///   - the [GemCell] map (visual cells, animated)
///   - the particle system
///   - the 1-second round timer
///   - the end-of-game callback (assigned by the host)
///
/// The controller drives a [Ticker] via [TickerProvider]. Every tick
/// advances particle physics + pending animations, then calls [notifyListeners].
class Match3Controller extends ChangeNotifier {
  Match3Controller({
    required TickerProvider vsync,
    Match3Logic? logic,
    this.onCellTap,
  })  : _vsync = vsync,
        logic = logic ?? Match3Logic(),
        _rng = Random() {
    _state = this.logic.newGame();
    _syncCellsFromGrid();
    _ticker = vsync.createTicker(_onTick);
  }

  // ignore: unused_field
  final TickerProvider _vsync;
  final Match3Logic logic;
  final Random _rng;

  late final Ticker _ticker;
  late Match3State _state;

  /// Visual cells keyed by (row, col). Order is preserved for paint.
  final Map<String, GemCell> _cells = {};

  /// Per-cell pixel offsets that animate over multiple frames.
  /// Each entry: cellKey → (currentOffset, targetOffset, framesLeft, totalFrames).
  final Map<String, _CellTween> _tweens = {};

  /// Active particle puffs.
  final List<GemParticle> _particles = [];

  /// Optional host callback for taps (used by the widget tree to detect
  /// which (row, col) was tapped — the controller works in abstract
  /// coordinates and never touches the widget tree).
  final void Function(GridPos pos)? onCellTap;

  /// The host-supplied end-of-game callback. Assigned via [attachEndCallback].
  void Function(int score)? _onGameEnd;

  Match3State get state => _state;

  /// Whether the controller has fired the end-of-game callback. The host
  /// checks this before pushing the rewards screen so a duplicate frame
  /// can't double-push.
  bool get hasEnded => _state.isEnded;

  void attachEndCallback(void Function(int score) cb) {
    _onGameEnd = cb;
  }

  // ---------------------------------------------------------------------
  // Lifecycle — implements GameModule shape but stays framework-agnostic.
  // The host wires init/pause/resume through this controller.
  // ---------------------------------------------------------------------

  void init() {
    if (!_ticker.isActive) _ticker.start();
  }

  void pause() {
    if (_state.isEnded) return;
    _state = _state.copyWith(isPaused: true);
    _ticker.stop();
    notifyListeners();
  }

  void resume() {
    if (_state.isEnded) return;
    _state = _state.copyWith(isPaused: false);
    if (!_ticker.isActive) _ticker.start();
    notifyListeners();
  }

  /// End the round — timer hit 0. Stops the ticker, fires the callback
  /// exactly once.
  void endDueToTimer() {
    if (_state.isEnded) return;
    _state = _state.copyWith(isEnded: true);
    _ticker.stop();
    notifyListeners();
    _onGameEnd?.call(_state.score);
  }

  // ---------------------------------------------------------------------
  // Tick
  // ---------------------------------------------------------------------

  Duration _lastTick = Duration.zero;
  Duration _accumulator = Duration.zero;

  void _onTick(Duration elapsed) {
    if (_state.isPaused || _state.isEnded) return;
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;

    // Timer.
    _accumulator += delta;
    if (_accumulator >= const Duration(seconds: 1)) {
      _accumulator = Duration.zero;
      final next = (_state.secondsRemaining - 1).clamp(0, 9999);
      _state = _state.copyWith(secondsRemaining: next);
      if (next == 0) {
        endDueToTimer();
        return;
      }
    }

    // Animate cells.
    final completed = <String>[];
    _tweens.forEach((key, tween) {
      tween.framesLeft -= 1;
      final t = 1 - (tween.framesLeft / tween.totalFrames).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
      tween.cell.offset = Offset.lerp(tween.from, tween.to, eased)!;
      if (tween.framesLeft <= 0) {
        tween.cell.offset = tween.to;
        completed.add(key);
      }
    });
    for (final key in completed) {
      _tweens.remove(key);
    }

    // Particles.
    final deltaMs = delta.inMicroseconds / 1000.0;
    final newParticles = <GemParticle>[];
    for (final p in _particles) {
      final remainingMs = p.lifeMs - deltaMs;
      if (remainingMs <= 0) continue;
      newParticles.add(
        GemParticle(
          color: p.color,
          position: p.position + p.velocity * (deltaMs / 16.6),
          velocity: p.velocity,
          lifeMs: remainingMs.round(),
          totalLifeMs: p.totalLifeMs,
          size: p.size,
        ),
      );
    }
    _particles
      ..clear()
      ..addAll(newParticles);

    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Player input
  // ---------------------------------------------------------------------

  GridPos? _firstTap;

  void onTap(GridPos pos) {
    if (_state.isPaused || _state.isEnded) return;
    onCellTap?.call(pos);

    final key = _cellKey(pos.row, pos.col);
    final tapped = _cells[key];
    if (tapped == null) return;

    if (_firstTap == null) {
      _firstTap = pos;
      tapped.selected = true;
      notifyListeners();
      return;
    }

    if (_firstTap == pos) {
      // Deselect.
      tapped.selected = false;
      _firstTap = null;
      notifyListeners();
      return;
    }

    final firstPos = _firstTap!;
    final firstKey = _cellKey(firstPos.row, firstPos.col);
    final firstCell = _cells[firstKey];
    _firstTap = null;
    if (firstCell != null) firstCell.selected = false;

    if (!logic.isAdjacent(firstPos, pos)) {
      // Treat as a fresh first tap.
      _firstTap = pos;
      tapped.selected = true;
      notifyListeners();
      return;
    }

    _applySwap(firstPos, pos);
  }

  void _applySwap(GridPos a, GridPos b) {
    final outcome = logic.processSwap(_state.grid, a, b);
    if (!outcome.hadEffect) {
      // Animate the failed swap: swap visually, then snap back.
      _animateSwap(a, b, thenSnapBack: true);
      return;
    }

    // 1. Animate the swap.
    _animateSwap(a, b);

    // 2. Compute scoring.
    final cascadeBonus = (outcome.maxCascadeLevel - 1) * 5;
    final gemsScore = outcome.clearedCount * 10 + cascadeBonus;

    // 3. Schedule clear + drop. We rebuild the cells to match the new
    //    grid and animate the drop.
    _scheduleClearAndDrop(outcome.newGrid, gemsScore);
  }

  void _animateSwap(GridPos a, GridPos b, {bool thenSnapBack = false}) {
    final cellA = _cells[_cellKey(a.row, a.col)];
    final cellB = _cells[_cellKey(b.row, b.col)];
    if (cellA == null || cellB == null) return;

    // Convert cell centers to offsets assuming the host widget will use
    // the same grid geometry when laying them out.
    final sizeA = Offset(_cellSize, 0);
    final sizeB = Offset(_cellSize, 0);
    final offset = (b.col - a.col).sign * _cellSize;

    _startTween(cellA, Offset.zero, Offset(offset, 0), 8);
    _startTween(cellB, Offset.zero, Offset(-offset, 0), 8);

    if (thenSnapBack) {
      // Swap-back happens visually by reverse-moving after 8 frames.
      _tweens[_cellKey(a.row, a.col)] = _CellTween(
        cell: cellA,
        from: Offset(offset, 0),
        to: Offset.zero,
        framesLeft: 8,
        totalFrames: 8,
      );
      _tweens[_cellKey(b.row, b.col)] = _CellTween(
        cell: cellB,
        from: Offset(-offset, 0),
        to: Offset.zero,
        framesLeft: 8,
        totalFrames: 8,
      );
    } else {
      // Commit the swap logically — the new grid will be loaded when
      // the drop animation kicks in.
      _state = _state.copyWith(grid: _swapGridCells(_state.grid, a, b));
      notifyListeners();
    }
    // Suppress unused warning for cellSize / sizeA / sizeB.
    sizeA.toString();
    sizeB.toString();
  }

  List<List<GemType>> _swapGridCells(
    List<List<GemType>> grid,
    GridPos a,
    GridPos b,
  ) {
    final copy = List<List<GemType>>.generate(
      grid.length,
      (r) => List<GemType>.generate(grid[r].length, (c) => grid[r][c]),
    );
    final tmp = copy[a.row][a.col];
    copy[a.row][a.col] = copy[b.row][b.col];
    copy[b.row][b.col] = tmp;
    return copy;
  }

  void _scheduleClearAndDrop(List<List<GemType>> newGrid, int scoreDelta) {
    // 1. Find cells about to be cleared and mark them highlighted.
    final cleared = logic.findMatches(newGrid);
    final newState = _state.copyWith(
      grid: newGrid,
      score: _state.score + scoreDelta,
    );

    // 2. Spawn particles at cleared cells.
    final particleColors = <GemType, Color>{
      GemType.ruby: const Color(0xFFEF4444),
      GemType.amethyst: const Color(0xFFA855F7),
      GemType.topaz: const Color(0xFFFBBF24),
      GemType.emerald: const Color(0xFF22C55E),
      GemType.sapphire: const Color(0xFF3B82F6),
      GemType.diamond: const Color(0xFFE2E8F0),
    };
    for (final pos in cleared) {
      final cell = _cells[_cellKey(pos.row, pos.col)];
      if (cell == null) continue;
      cell.highlighted = true;
      final center = _cellCenter(pos.row, pos.col);
      for (int i = 0; i < 4; i++) {
        final angle = _rng.nextDouble() * pi * 2;
        final speed = 60 + _rng.nextDouble() * 80;
        _particles.add(
          GemParticle(
            color: particleColors[cell.type] ?? Colors.white,
            position: center,
            velocity: Offset(cos(angle), sin(angle)) * speed,
            lifeMs: 600,
            totalLifeMs: 600,
            size: 4 + _rng.nextDouble() * 4,
          ),
        );
      }
    }

    // 3. After the highlight phase (6 frames), scale the cleared cells
    //    down to 0 and drop the new grid into place.
    _state = newState;
    _afterFrames(6, () {
      // Remove cleared cells, then rebuild from the new grid.
      for (final pos in cleared) {
        _cells.remove(_cellKey(pos.row, pos.col));
      }
      _syncCellsFromGrid(animateDrop: true);
    });
  }

  // ---------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------

  void _syncCellsFromGrid({bool animateDrop = false}) {
    // Mark cells that already exist with new types. Cells that disappear
    // are removed. New cells appear at row -1 (above the grid) and drop.
    final newKeys = <String>{};
    for (int r = 0; r < logic.gridSize; r++) {
      for (int c = 0; c < logic.gridSize; c++) {
        final key = _cellKey(r, c);
        newKeys.add(key);
        final existing = _cells[key];
        if (existing != null) {
          existing.type = _state.grid[r][c];
          existing.targetRow = r;
          existing.targetCol = c;
        } else {
          _cells[key] = GemCell(
            type: _state.grid[r][c],
            targetRow: r,
            targetCol: c,
            offset: animateDrop ? const Offset(0, -_cellSize) : Offset.zero,
          );
        }
      }
    }
    _cells.removeWhere((k, _) => !newKeys.contains(k));
    if (animateDrop) {
      // Drop tweens.
      for (final cell in _cells.values) {
        _startTween(cell, cell.offset, Offset.zero, 10);
      }
    }
  }

  void _afterFrames(int n, VoidCallback cb) {
    int remaining = n;
    void listener() {
      remaining--;
      if (remaining <= 0) {
        removeListener(listener);
        cb();
      }
    }

    addListener(listener);
  }

  void _startTween(GemCell cell, Offset from, Offset to, int frames) {
    final key = '${cell.targetRow}:${cell.targetCol}:${identityHashCode(cell)}';
    _tweens[key] = _CellTween(
      cell: cell,
      from: from,
      to: to,
      framesLeft: frames,
      totalFrames: frames,
    );
  }

  Offset _cellCenter(int row, int col) {
    return Offset(
      col * _cellSize + _cellSize / 2,
      row * _cellSize + _cellSize / 2,
    );
  }

  // ---------------------------------------------------------------------
  // Public accessors the widget needs.
  // ---------------------------------------------------------------------

  List<GemCell> get visibleCells => _cells.values.toList(growable: false);
  List<GemParticle> get particles => List.unmodifiable(_particles);
  double get cellSize => _cellSize;
  int get gridSize => logic.gridSize;

  // ---------------------------------------------------------------------
  // Static cell size — kept simple: the widget tree asks for it and
  // sizes each cell accordingly. Real pixel size is decided by the
  // Match3Game widget based on its render box.
  // ---------------------------------------------------------------------
  static const double _cellSize = 44.0;

  String _cellKey(int r, int c) => '$r:$c';

  @override
  void dispose() {
    _ticker.dispose();
    _tweens.clear();
    _cells.clear();
    _particles.clear();
    super.dispose();
  }
}

class _CellTween {
  _CellTween({
    required this.cell,
    required this.from,
    required this.to,
    required this.framesLeft,
    required this.totalFrames,
  });
  final GemCell cell;
  Offset from;
  Offset to;
  int framesLeft;
  int totalFrames;
}