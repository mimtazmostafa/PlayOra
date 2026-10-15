/// Pure data model for the Bubble Shooter game.
///
/// The board is a hex grid with offset rows: even rows start at column 0,
/// odd rows are shifted by half a cell so the bubbles interlock. We
/// represent an empty cell as `null` and a filled cell as a [BubbleColor].
///
/// The grid is constant-width: 12 columns × 16 rows. Row 0 is the top
/// (ceiling) and row 15 is at the bottom near the launcher. The
/// "ceiling line" sits at row 5 — when any bubble crosses it, the game
/// ends.
///
/// Coordinate convention:
///   - [row] is 0..15, top to bottom
///   - [col] is 0..11, left to right
///   - odd rows are shifted by half a cell width visually, but we still
///     index them at integer columns and the renderer handles the offset
///
/// Match-3 pop rule: a bubble is cleared when it has ≥ 2 same-color
/// neighbors in the 6 hex directions. After every pop, surviving bubbles
/// are checked for support — any bubble that no longer connects to the
/// ceiling row is orphaned and removed (free dropping bubbles).
library;

import 'dart:math' as math;

/// The distinct colors a bubble can have. `none` is reserved for empty
/// cells and is encoded as `null` in the board matrix.
enum BubbleColor {
  red,
  blue,
  green,
  yellow,
  purple,
}

/// Geometric constants for the board layout.
class BubbleBoardSpec {
  BubbleBoardSpec({
    this.columns = 12,
    this.rows = 16,
    this.ceilingLine = 5,
  });

  final int columns;
  final int rows;
  /// The first row at which a bubble is allowed to leave the ceiling.
  /// The classic game uses ~5–7 depending on board height. When the
  /// board fills with a bubble at or below this row, the player loses.
  final int ceilingLine;

  /// Const-friendly default spec used in the `initial()` factory's
  /// default. Kept as a separate instance because `BubbleBoardSpec` is
  /// not const-constructible (the runtime default has to live in
  /// [BubbleShooterState.defaultSpec]).
  static const BubbleBoardSpec defaultSpec = BubbleBoardSpec._(
    columns: 12,
    rows: 16,
    ceilingLine: 5,
  );

  /// Looser spec used for game surfaces where instant-loss feels
  /// unfair (the casual `Bubble Pop` tile). 4 start rows gives the
  /// player enough empty rows to play, and a ceiling line of 10 (out
  /// of 16 total) leaves a large buffer before the board is "full".
  static const BubbleBoardSpec casualSpec = BubbleBoardSpec._(
    columns: 12,
    rows: 16,
    ceilingLine: 10,
  );

  const BubbleBoardSpec._({
    required this.columns,
    required this.rows,
    required this.ceilingLine,
  });
}

/// Pure, deterministic representation of the bubble board.
///
/// The model is immutable: every mutation returns a new
/// [BubbleShooterState]. The controller drives animations and the
/// Ticker, but the rules engine here is reproducible and unit-testable.
class BubbleShooterState {
  BubbleShooterState({
    required this.board,
    required this.score,
    required this.shotsTaken,
    required this.ceilingLine,
    required this.scoreTarget,
    this.status = BubbleGameStatus.ongoing,
  })  : assert(board.length == 16 * 12,
            'Board must be a 16×12 grid flattened to 192 slots'),
        assert(ceilingLine >= 0 && ceilingLine < 16,
            'Ceiling line must be within the board');

  /// Returns a fresh state with the launcher filled with [startRows]
  /// rows of random colored bubbles at the top.
  factory BubbleShooterState.initial({
    required math.Random rng,
    int startRows = 5,
    BubbleBoardSpec spec = BubbleBoardSpec.defaultSpec,
  }) {
    final board = List<BubbleColor?>.filled(
      spec.rows * spec.columns,
      null,
      growable: false,
    );
    // Ceiling row is half-density so it doesn't immediately look like a wall.
    for (var r = 0; r < startRows; r++) {
      final isEvenRow = r.isEven;
      final maxCol = isEvenRow ? spec.columns : spec.columns - 1;
      for (var c = 0; c < maxCol; c++) {
        board[r * spec.columns + c] = _randomColor(rng);
      }
    }
    return BubbleShooterState(
      board: board,
      score: 0,
      shotsTaken: 0,
      ceilingLine: spec.ceilingLine,
      scoreTarget: 1000,
    );
  }

  /// 192 slots: 16 rows × 12 cols. null = empty.
  final List<BubbleColor?> board;
  final int score;
  final int shotsTaken;
  final int ceilingLine;
  final int scoreTarget;
  final BubbleGameStatus status;

  static const int boardWidth = 12;
  static const int boardHeight = 16;
  static const int slotCount = boardWidth * boardHeight;

  bool get isGameOver => status != BubbleGameStatus.ongoing;

  /// Read the cell at ([row], [col]) or null if out of bounds.
  BubbleColor? at(int row, int col) {
    if (row < 0 || row >= boardHeight) return null;
    if (col < 0 || col >= boardWidth) return null;
    return board[row * boardWidth + col];
  }

  /// True if the projectile will land at this slot given the current
  /// board. We consider the slot "fillable" if it is empty AND its
  /// upper neighbors (which the projectile would have to bounce off)
  /// don't already block it. Practically: any empty cell that has at
  /// least one filled or wall neighbor above is a valid snap target.
  bool isValidSnapTarget(int row, int col) {
    if (row < 0 || row >= boardHeight) return false;
    if (col < 0 || col >= boardWidth) return false;
    if (at(row, col) != null) return false;
    return true;
  }

  /// Apply a shot of [shot] to the cell at ([row], [col]). Runs the
  /// match-3 pop rule, then drops any orphan bubbles, then updates
  /// the score and game status. Returns the new state.
  BubbleShooterState shoot({
    required int row,
    required int col,
    required BubbleColor shot,
    math.Random? rng,
  }) {
    if (status != BubbleGameStatus.ongoing) return this;
    if (row < 0 || row >= boardHeight || col < 0 || col >= boardWidth) {
      return this;
    }
    if (at(row, col) != null) return this; // Cell already occupied.

    final newBoard = List<BubbleColor?>.from(board);
    newBoard[row * boardWidth + col] = shot;

    // Pop connected same-color group of ≥ 3.
    final popped = _popCluster(newBoard, row, col, shot);
    var runningBoard = newBoard;
    var poppedCount = popped;

    // Chain: pops can leave orphans. After every pop batch, drop
    // floating bubbles. Repeat until a pop batch finds no cluster.
    while (poppedCount >= 3) {
      runningBoard = _dropOrphans(runningBoard);
      runningBoard = _addCeilingRowIfShotsPassed(runningBoard, rng);
      // We only need to check for new matches adjacent to the popped
      // cluster but cheapest is to scan the full board once.
      final newPop = _popAnyCluster(runningBoard);
      if (newPop == 0) break;
      poppedCount = newPop;
    }

    final runningScore = score + popped;
    final newShotsTaken = shotsTaken + 1;

    final newStatus = _evaluateStatus(
      runningBoard,
      runningScore,
      newShotsTaken,
    );

    return BubbleShooterState(
      board: runningBoard,
      score: runningScore,
      shotsTaken: newShotsTaken,
      ceilingLine: ceilingLine,
      scoreTarget: scoreTarget,
      status: newStatus,
    );
  }

  /// Returns the popped count if the new bubble is the trigger;
  /// callers use this to decide if they should drop orphans.
  int _popCluster(
    List<BubbleColor?> board,
    int row,
    int col,
    BubbleColor shot,
  ) {
    final visited = <int>{};
    final queue = <List<int>>[
      [row, col]
    ];
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      final r = cell[0];
      final c = cell[1];
      final idx = r * boardWidth + c;
      if (visited.contains(idx)) continue;
      if (board[idx] != shot) continue;
      visited.add(idx);
      for (final n in _neighbors(r, c)) {
        if (board[n[0] * boardWidth + n[1]] == shot) {
          queue.add(n);
        }
      }
    }
    if (visited.length < 3) return 0;
    for (final idx in visited) {
      board[idx] = null;
    }
    return visited.length;
  }

  /// Scans the entire board for any cluster of ≥ 3 same-color bubbles
  /// and pops it. Returns the popped count, or 0 if none found.
  int _popAnyCluster(List<BubbleColor?> board) {
    final visited = <int>{};
    for (var i = 0; i < board.length; i++) {
      if (board[i] == null || visited.contains(i)) continue;
      final r = i ~/ boardWidth;
      final c = i % boardWidth;
      final cluster = <int>{i};
      final queue = <List<int>>[
        [r, c]
      ];
      while (queue.isNotEmpty) {
        final cell = queue.removeLast();
        final cr = cell[0];
        final cc = cell[1];
        final idx = cr * boardWidth + cc;
        if (cluster.contains(idx)) continue;
        if (board[idx] != board[i]) continue;
        cluster.add(idx);
        for (final n in _neighbors(cr, cc)) {
          queue.add(n);
        }
      }
      if (cluster.length >= 3) {
        for (final idx in cluster) {
          board[idx] = null;
        }
        visited.addAll(cluster);
        return cluster.length;
      }
      visited.addAll(cluster);
    }
    return 0;
  }

  /// Removes any bubble that does not have a path through filled cells
  /// to the ceiling row.
  List<BubbleColor?> _dropOrphans(List<BubbleColor?> board) {
    final connected = <int>{};
    // BFS from the ceiling row.
    for (var c = 0; c < boardWidth; c++) {
      if (board[c] != null) {
        connected.add(c);
        _bfsFrom(board, 0, c, connected);
      }
    }
    final result = List<BubbleColor?>.from(board);
    for (var i = 0; i < result.length; i++) {
      if (result[i] != null && !connected.contains(i)) {
        result[i] = null;
      }
    }
    return result;
  }

  void _bfsFrom(
    List<BubbleColor?> board,
    int row,
    int col,
    Set<int> visited,
  ) {
    final idx = row * boardWidth + col;
    if (visited.contains(idx)) return;
    visited.add(idx);
    for (final n in _neighbors(row, col)) {
      final nIdx = n[0] * boardWidth + n[1];
      if (visited.contains(nIdx)) continue;
      if (board[nIdx] == null) continue;
      visited.add(nIdx);
      _bfsFrom(board, n[0], n[1], visited);
    }
  }

  /// Every ~6 shots, drop a new ceiling row to keep the game tense.
  List<BubbleColor?> _addCeilingRowIfShotsPassed(
    List<BubbleColor?> board,
    math.Random? rng,
  ) {
    if (rng == null) return board;
    if (shotsTaken % 6 != 0) return board;
    // Shift everything down by one row, drop the bottom row, fill the
    // top row with new random colors.
    final result = List<BubbleColor?>.filled(board.length, null);
    for (var r = 1; r < boardHeight; r++) {
      for (var c = 0; c < boardWidth; c++) {
        final from = r * boardWidth + c;
        final to = (r - 1) * boardWidth + c;
        if (r * boardWidth + c < board.length) {
          result[to] = board[from];
        }
      }
    }
    // Fill the new bottom row.
    final bottomRow = boardHeight - 1;
    final isEvenRow = bottomRow.isEven;
    final maxCol = isEvenRow ? boardWidth : boardWidth - 1;
    for (var c = 0; c < maxCol; c++) {
      result[bottomRow * boardWidth + c] = _randomColor(rng);
    }
    return result;
  }

  BubbleGameStatus _evaluateStatus(
    List<BubbleColor?> board,
    int score,
    int shotsTaken,
  ) {
    // Win: score target reached.
    if (score >= scoreTarget) return BubbleGameStatus.won;
    // Loss: any filled cell at or below the ceiling line.
    for (var r = ceilingLine; r < boardHeight; r++) {
      for (var c = 0; c < boardWidth; c++) {
        if (board[r * boardWidth + c] != null) {
          return BubbleGameStatus.lost;
        }
      }
    }
    // Soft loss: more than 60 shots (player is dragging their feet).
    if (shotsTaken > 60) return BubbleGameStatus.lost;
    return BubbleGameStatus.ongoing;
  }

  /// Yields the 6 hex neighbors of ([row], [col]) using the offset
  /// convention. Even rows have direct left/right neighbors at the same
  /// column; odd rows are shifted half a cell which means their left
  /// neighbor is at column-1 and right neighbor is at column+1 in the
  /// row above.
  static List<List<int>> _neighbors(int row, int col) {
    final isEvenRow = row.isEven;
    final left = isEvenRow ? col - 1 : col;
    final right = isEvenRow ? col + 1 : col + 2;
    final upperLeft = isEvenRow ? col - 1 : col;
    final upperRight = isEvenRow ? col : col + 1;
    final lowerLeft = isEvenRow ? col - 1 : col;
    final lowerRight = isEvenRow ? col : col + 1;
    return [
      [row - 1, upperLeft],
      [row - 1, upperRight],
      [row, left],
      [row, right],
      [row + 1, lowerLeft],
      [row + 1, lowerRight],
    ];
  }

  /// Counts how many cells of [color] are alive on the board. Used
  /// for the scoring-multiplier heuristic in the AI aim.
  int countOf(BubbleColor color) {
    var n = 0;
    for (final cell in board) {
      if (cell == color) n++;
    }
    return n;
  }

  /// Total filled cells on the board.
  int get filledCount {
    var n = 0;
    for (final cell in board) {
      if (cell != null) n++;
    }
    return n;
  }

  static BubbleColor _randomColor(math.Random rng) {
    return BubbleColor.values[rng.nextInt(BubbleColor.values.length)];
  }

  /// Returns the highest row index that contains a filled cell, or
  /// -1 if the board is empty. Useful for the "ceiling warning" line.
  int get highestFilledRow {
    for (var r = 0; r < boardHeight; r++) {
      for (var c = 0; c < boardWidth; c++) {
        if (board[r * boardWidth + c] != null) return r;
      }
    }
    return -1;
  }

  BubbleShooterState copyWith({
    List<BubbleColor?>? board,
    int? score,
    int? shotsTaken,
    BubbleGameStatus? status,
  }) {
    return BubbleShooterState(
      board: board ?? this.board,
      score: score ?? this.score,
      shotsTaken: shotsTaken ?? this.shotsTaken,
      ceilingLine: ceilingLine,
      scoreTarget: scoreTarget,
      status: status ?? this.status,
    );
  }
}

/// Possible outcomes of a bubble game round.
enum BubbleGameStatus {
  ongoing,
  won,
  lost,
}
