import 'dart:math';

/// The six gem colors used in Match-3 (kept readable on a purple backdrop).
enum GemType {
  ruby,
  amethyst,
  topaz,
  emerald,
  sapphire,
  diamond;

  /// Built once per process — order is the visual enum order, not the
  /// wire format. Used in the grid model.
  static final List<GemType> allTypes = GemType.values;

  static GemType random(Random rng) => allTypes[rng.nextInt(6)];
}

/// A single 2D coordinate inside the grid.
class GridPos {
  const GridPos(this.row, this.col);
  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GridPos && other.row == row && other.col == col);

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'GridPos($row, $col)';
}

/// Plain-data game state. Intentionally NOT a Dart class with mutable
/// fields — the [Match3Controller] rebuilds a fresh snapshot for every
/// frame so tests can compare snapshots deterministically.
class Match3State {
  const Match3State({
    required this.grid,
    required this.score,
    required this.secondsRemaining,
    required this.isPaused,
    required this.isEnded,
    required this.cascadeLevel,
  });

  /// `grid[row][col]`. Rows top-to-bottom, cols left-to-right.
  final List<List<GemType>> grid;
  final int score;
  final int secondsRemaining;
  final bool isPaused;
  final bool isEnded;

  /// Tracks the current cascade chain depth — used by the match engine
  /// to award a bonus and stop infinite recursion.
  final int cascadeLevel;

  Match3State copyWith({
    List<List<GemType>>? grid,
    int? score,
    int? secondsRemaining,
    bool? isPaused,
    bool? isEnded,
    int? cascadeLevel,
  }) {
    return Match3State(
      grid: grid ?? this.grid,
      score: score ?? this.score,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      isPaused: isPaused ?? this.isPaused,
      isEnded: isEnded ?? this.isEnded,
      cascadeLevel: cascadeLevel ?? this.cascadeLevel,
    );
  }
}

/// Pure functions that operate on a [Match3State]. Kept separate from
/// the controller so they can be unit-tested without a Ticker.
class Match3Logic {
  Match3Logic({this.gridSize = 7, this.roundSeconds = 60, int? seed})
      : _rng = Random(seed);

  final int gridSize;
  final int roundSeconds;
  final Random _rng;

  /// Build the initial board. We re-roll any cell that immediately
  /// participates in a 3+ match so the player is never shown a "solved"
  /// board at t=0.
  Match3State newGame() {
    while (true) {
      final grid = _randomGrid();
      if (_findMatches(grid).isEmpty) {
        return Match3State(
          grid: grid,
          score: 0,
          secondsRemaining: roundSeconds,
          isPaused: false,
          isEnded: false,
          cascadeLevel: 0,
        );
      }
    }
  }

  List<List<GemType>> _randomGrid() {
    return List<List<GemType>>.generate(
      gridSize,
      (_) => List<GemType>.generate(
        gridSize,
        (_) => GemType.random(_rng),
      ),
    );
  }

  /// True if [a] and [b] are orthogonally adjacent.
  bool isAdjacent(GridPos a, GridPos b) {
    final dr = (a.row - b.row).abs();
    final dc = (a.col - b.col).abs();
    return (dr + dc) == 1;
  }

  /// Swap two cells immutably. Returns the new grid (or `null` if the
  /// positions are out of bounds / identical).
  List<List<GemType>>? swap(
    List<List<GemType>> grid,
    GridPos a,
    GridPos b,
  ) {
    if (!_inBounds(a) || !_inBounds(b) || a == b) return null;
    final copy = _copyGrid(grid);
    final tmp = copy[a.row][a.col];
    copy[a.row][a.col] = copy[b.row][b.col];
    copy[b.row][b.col] = tmp;
    return copy;
  }

  /// Locate every horizontal and vertical run of 3+ same-color gems.
  /// Returns the union of unique positions that should be cleared.
  Set<GridPos> _findMatches(List<List<GemType>> grid) {
    final out = <GridPos>{};

    // Horizontal runs.
    for (int r = 0; r < gridSize; r++) {
      int runStart = 0;
      while (runStart < gridSize) {
        int runEnd = runStart + 1;
        while (runEnd < gridSize && grid[r][runEnd] == grid[r][runStart]) {
          runEnd++;
        }
        if (runEnd - runStart >= 3) {
          for (int c = runStart; c < runEnd; c++) {
            out.add(GridPos(r, c));
          }
        }
        runStart = runEnd;
      }
    }

    // Vertical runs.
    for (int c = 0; c < gridSize; c++) {
      int runStart = 0;
      while (runStart < gridSize) {
        int runEnd = runStart + 1;
        while (runEnd < gridSize && grid[runEnd][c] == grid[runStart][c]) {
          runEnd++;
        }
        if (runEnd - runStart >= 3) {
          for (int r = runStart; r < runEnd; r++) {
            out.add(GridPos(r, c));
          }
        }
        runStart = runEnd;
      }
    }

    return out;
  }

  /// Public for tests. Re-exported so the controller can show a hint
  /// overlay if it ever wants to.
  Set<GridPos> findMatches(List<List<GemType>> grid) => _findMatches(grid);

  /// Drop everything above a cleared cell down by one, then fill the
  /// top row with new random gems. Returns the new grid AND the
  /// positions that were cleared (so the controller can schedule a
  /// "pop" animation).
  GameStepResult resolveCleared(List<List<GemType>> grid, Set<GridPos> cleared) {
    if (cleared.isEmpty) {
      return GameStepResult(grid: grid, cleared: const <GridPos>{});
    }

    // Replace each cleared cell with `null` sentinel, then compact.
    final working = List<List<GemType?>>.generate(
      gridSize,
      (r) => List<GemType?>.generate(
        gridSize,
        (c) => cleared.contains(GridPos(r, c)) ? null : grid[r][c],
      ),
    );

    // For each column, drop everything down.
    for (int c = 0; c < gridSize; c++) {
      int writeRow = gridSize - 1;
      for (int r = gridSize - 1; r >= 0; r--) {
        final cell = working[r][c];
        if (cell != null) {
          working[writeRow][c] = cell;
          if (writeRow != r) working[r][c] = null;
          writeRow--;
        }
      }
      // Fill the top with fresh gems.
      for (int r = writeRow; r >= 0; r--) {
        working[r][c] = GemType.random(_rng);
      }
    }

    final newGrid = List<List<GemType>>.generate(
      gridSize,
      (r) => List<GemType>.generate(
        gridSize,
        (c) => working[r][c] ?? GemType.random(_rng),
      ),
    );
    return GameStepResult(grid: newGrid, cleared: cleared);
  }

  /// Process a full swap → resolve → cascade round.
  ///
  /// Returns the final grid + total gems cleared (for scoring) + cascade
  /// chain depth. Caller is responsible for adding to the score.
  SwapOutcome processSwap(
    List<List<GemType>> grid,
    GridPos a,
    GridPos b,
  ) {
    final swapped = swap(grid, a, b);
    if (swapped == null) {
      return SwapOutcome(
        newGrid: grid,
        clearedCount: 0,
        maxCascadeLevel: 0,
        hadEffect: false,
      );
    }
    final matches = _findMatches(swapped);
    if (matches.isEmpty) {
      // No match — "swap back" by returning the original grid.
      return SwapOutcome(
        newGrid: grid,
        clearedCount: 0,
        maxCascadeLevel: 0,
        hadEffect: false,
      );
    }

    var current = swapped;
    var totalCleared = matches.length;
    var cascadeLevel = 1;
    final visited = <Set<GridPos>>{matches};

    while (true) {
      final step = resolveCleared(current, matches);
      current = step.grid;
      final nextMatches = _findMatches(current);
      if (nextMatches.isEmpty) break;
      // Avoid infinite loops if the same exact pattern reappears.
      final signature = nextMatches.toSet();
      bool alreadySeen = visited.any((set) => _setEquals(set, signature));
      if (alreadySeen) break;
      visited.add(signature);
      totalCleared += nextMatches.length;
      cascadeLevel++;
      matches
        ..clear()
        ..addAll(nextMatches);
    }

    return SwapOutcome(
      newGrid: current,
      clearedCount: totalCleared,
      maxCascadeLevel: cascadeLevel,
      hadEffect: true,
    );
  }

  bool _inBounds(GridPos p) =>
      p.row >= 0 && p.row < gridSize && p.col >= 0 && p.col < gridSize;

  List<List<GemType>> _copyGrid(List<List<GemType>> grid) =>
      List<List<GemType>>.generate(
        gridSize,
        (r) => List<GemType>.generate(gridSize, (c) => grid[r][c]),
      );

  static bool _setEquals(Set<GridPos> a, Set<GridPos> b) {
    if (a.length != b.length) return false;
    for (final p in a) {
      if (!b.contains(p)) return false;
    }
    return true;
  }
}

/// Result of dropping + refilling after a clear.
class GameStepResult {
  const GameStepResult({required this.grid, required this.cleared});
  final List<List<GemType>> grid;
  final Set<GridPos> cleared;
}

/// Result of one player-initiated swap.
class SwapOutcome {
  const SwapOutcome({
    required this.newGrid,
    required this.clearedCount,
    required this.maxCascadeLevel,
    required this.hadEffect,
  });

  /// The grid state the player should see AFTER the swap resolves.
  /// If no match was made, this is the ORIGINAL grid (swap is animated
  /// back, no score, no cascade).
  final List<List<GemType>> newGrid;

  /// Total number of gems cleared this swap (across all cascade levels).
  final int clearedCount;

  /// Maximum cascade level reached during resolution (1 = first match).
  final int maxCascadeLevel;

  /// True if the swap produced at least one match. False means the
  /// swap should play a "bounce back" animation and not change the score.
  final bool hadEffect;
}