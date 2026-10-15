import 'dart:math';

/// 1010-style block puzzle. The player drags tetromino-shaped pieces onto
/// a 10x10 grid; fully filled rows and columns are cleared and award
/// combo points. The game ends when none of the three pieces on the tray
/// can be placed anywhere on the board.
///
/// All functions in [BlockPuzzleLogic] are pure — they take a [BoardState]
/// and return a new one. The controller owns the [Ticker] and decides
/// when to call them. Tests can drive the logic without a Ticker.

/// A grid cell. `null` means empty; non-null means the cell is filled
/// (with the piece id that filled it, useful for color variety).
typedef BoardCell = String?;

/// A board of fixed size with two possible states per cell: empty or
/// filled. We store piece ids so the renderer can color cells by which
/// piece they came from.
class BoardGrid {
  BoardGrid(this.size, [List<List<BoardCell>>? cells])
      : cells = cells ??
            List<List<BoardCell>>.generate(
              size,
              (_) => List<BoardCell>.filled(size, null),
            );

  final int size;
  final List<List<BoardCell>> cells;

  BoardCell getCell(int r, int c) => cells[r][c];
  bool isFilled(int r, int c) => cells[r][c] != null;
  bool inBounds(int r, int c) =>
      r >= 0 && r < size && c >= 0 && c < size;

  /// Return a deep copy of the grid (for immutable updates).
  BoardGrid copy() => BoardGrid(
        size,
        List<List<BoardCell>>.generate(
          size,
          (r) => List<BoardCell>.generate(size, (c) => cells[r][c]),
        ),
      );
}

/// The five canonical piece shapes used in classic 1010. Each is a list
/// of (row, col) offsets relative to the piece's top-left bounding box.
/// Stored as constant lists so we don't allocate per-frame.
class BlockShapes {
  BlockShapes._();

  /// Single cell.
  static const List<List<List<int>>> all = <List<List<int>>>[
    // 1x1 dot.
    [
      [0, 0],
    ],
    // 1x2 domino.
    [
      [0, 0],
      [0, 1],
    ],
    // 1x3 triomino.
    [
      [0, 0],
      [0, 1],
      [0, 2],
    ],
    // 1x4 tetromino line.
    [
      [0, 0],
      [0, 1],
      [0, 2],
      [0, 3],
    ],
    // 1x5 pentomino line.
    [
      [0, 0],
      [0, 1],
      [0, 2],
      [0, 3],
      [0, 4],
    ],
  ];

  /// Indices of the standard 1010 "easy" tray — one of each small shape
  /// plus a line. The tray is random, so we draw uniformly from `all`.
  static const List<int> easyMix = [0, 1, 1, 2, 2, 3, 4];
}

/// A single piece in the tray. Immutable.
class BlockPiece {
  const BlockPiece({
    required this.id,
    required this.shapeIndex,
    required this.cells,
  });

  /// Stable identifier for coloring / animations.
  final int id;

  /// Index into [BlockShapes.all]. The controller picks a new id each
  /// draw so successive identical shapes still look distinct.
  final int shapeIndex;

  /// Offsets in (row, col) form, relative to the piece's top-left.
  final List<List<int>> cells;

  /// Bounding-box width in cells.
  int get width =>
      cells.map((c) => c[1]).reduce((a, b) => a > b ? a : b) + 1;

  /// Bounding-box height in cells.
  int get height =>
      cells.map((c) => c[0]).reduce((a, b) => a > b ? a : b) + 1;
}

/// Pure logic. No Ticker. No mutable fields besides the seeded RNG.
class BlockPuzzleLogic {
  BlockPuzzleLogic({
    this.boardSize = 10,
    this.traySize = 3,
    int? seed,
  }) : _rng = Random(seed);

  final int boardSize;
  final int traySize;
  final Random _rng;

  /// All cells in the current board. Iterated for game-over detection.
  bool isGameOver(BoardGrid board, List<BlockPiece> tray) {
    for (final piece in tray) {
      if (canPlaceAnywhere(board, piece)) return false;
    }
    return true;
  }

  /// Returns a list of (topRow, leftCol) positions where the piece fits
  /// without overlapping or leaving the board. Used by the controller
  /// for "valid placement" highlights.
  List<List<int>> validPlacements(BoardGrid board, BlockPiece piece) {
    final out = <List<int>>[];
    for (int r = 0; r <= boardSize - piece.height; r++) {
      for (int c = 0; c <= boardSize - piece.width; c++) {
        if (_canPlaceAt(board, piece, r, c)) {
          out.add(<int>[r, c]);
        }
      }
    }
    return out;
  }

  /// True if the piece can be placed somewhere on the board.
  bool canPlaceAnywhere(BoardGrid board, BlockPiece piece) {
    for (int r = 0; r <= boardSize - piece.height; r++) {
      for (int c = 0; c <= boardSize - piece.width; c++) {
        if (_canPlaceAt(board, piece, r, c)) return true;
      }
    }
    return false;
  }

  /// True if the piece fits at exactly (topRow, leftCol) — all cells in
  /// bounds and all cells empty.
  bool _canPlaceAt(BoardGrid board, BlockPiece piece, int topRow, int leftCol) {
    for (final cell in piece.cells) {
      final r = topRow + cell[0];
      final c = leftCol + cell[1];
      if (!board.inBounds(r, c)) return false;
      if (board.isFilled(r, c)) return false;
    }
    return true;
  }

  /// Try to place the piece. Returns null if the move is invalid; the
  /// caller should play a "bounce" animation and not consume a piece.
  BlockPuzzleStep? placePiece({
    required BoardGrid board,
    required BlockPiece piece,
    required int topRow,
    required int leftCol,
  }) {
    if (!_canPlaceAt(board, piece, topRow, leftCol)) return null;

    final newBoard = board.copy();
    for (final cell in piece.cells) {
      final r = topRow + cell[0];
      final c = leftCol + cell[1];
      newBoard.cells[r][c] = 'p${piece.id}';
    }

    // After placing, clear any full rows and columns.
    final clearResult = _clearLines(newBoard);
    return BlockPuzzleStep(
      board: newBoard,
      clearedRows: clearResult.rows,
      clearedCols: clearResult.cols,
      cellsPlaced: piece.cells.length,
    );
  }

  /// Find and clear all full rows and columns. Returns the indices
  /// cleared so the renderer can flash them.
  _ClearResult _clearLines(BoardGrid board) {
    final fullRows = <int>[];
    for (int r = 0; r < boardSize; r++) {
      bool full = true;
      for (int c = 0; c < boardSize; c++) {
        if (!board.isFilled(r, c)) {
          full = false;
          break;
        }
      }
      if (full) fullRows.add(r);
    }

    final fullCols = <int>[];
    for (int c = 0; c < boardSize; c++) {
      bool full = true;
      for (int r = 0; r < boardSize; r++) {
        if (!board.isFilled(r, c)) {
          full = false;
          break;
        }
      }
      if (full) fullCols.add(c);
    }

    for (final r in fullRows) {
      for (int c = 0; c < boardSize; c++) {
        board.cells[r][c] = null;
      }
    }
    for (final c in fullCols) {
      for (int r = 0; r < boardSize; r++) {
        board.cells[r][c] = null;
      }
    }

    return _ClearResult(rows: fullRows, cols: fullCols);
  }

  /// Draw a new piece from the shape pool. Each draw gets a unique id so
  /// the renderer can color cells by id (avoids two same-shape pieces
  /// looking like one piece in the grid).
  BlockPiece drawPiece() {
    final shapeIndex = _rng.nextInt(BlockShapes.all.length);
    final cells = BlockShapes.all[shapeIndex];
    final id = _rng.nextInt(1 << 30);
    return BlockPiece(id: id, shapeIndex: shapeIndex, cells: cells);
  }

  /// Build an initial tray of [traySize] random pieces.
  List<BlockPiece> initialTray() {
    return List<BlockPiece>.generate(traySize, (_) => drawPiece());
  }
}

/// Result of a single placement.
class BlockPuzzleStep {
  const BlockPuzzleStep({
    required this.board,
    required this.clearedRows,
    required this.clearedCols,
    required this.cellsPlaced,
  });

  final BoardGrid board;
  final List<int> clearedRows;
  final List<int> clearedCols;

  /// Number of cells the piece occupied (used for base scoring).
  final int cellsPlaced;

  /// How many full lines (rows + columns) were cleared this placement.
  int get linesCleared => clearedRows.length + clearedCols.length;
}

class _ClearResult {
  const _ClearResult({required this.rows, required this.cols});
  final List<int> rows;
  final List<int> cols;
}
