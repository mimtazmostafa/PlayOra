import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'block_puzzle_state.dart';

/// Top-level controller for the Block Puzzle game.
///
/// State that changes every frame:
///   - the [BoardGrid]
///   - the tray of three pieces
///   - the score
///   - the currently-dragged piece + the (row, col) the player is hovering
///   - which rows/columns to flash for the line-clear animation
///
/// The controller drives a [Ticker] only for the animation queue
/// (line-clear flash, drop pieces, etc.). Pure logic lives in
/// [BlockPuzzleLogic].
class BlockPuzzleController extends ChangeNotifier {
  BlockPuzzleController({
    required TickerProvider vsync,
    BlockPuzzleLogic? logic,
  })  : _vsync = vsync,
        logic = logic ?? BlockPuzzleLogic() {
    _state = _State.initial(this.logic);
    _ticker = vsync.createTicker(_onTick);
  }

  // ignore: unused_field
  final TickerProvider _vsync;
  final BlockPuzzleLogic logic;

  late final Ticker _ticker;
  late _State _state;

  /// Player's hover preview — (row, col) of the top-left of the piece
  /// being dragged. `null` when no piece is being dragged.
  List<int>? _hoverAt;
  List<int>? _hoverPieceIndex;

  /// Flashing rows/columns from the most recent line clear. The widget
  /// uses these to play a "pop" animation; the controller clears them
  /// after a few frames.
  List<int> _flashingRows = const [];
  List<int> _flashingCols = const [];
  int _flashFramesLeft = 0;

  /// The host's end-of-game callback. Assigned via [attachEndCallback].
  void Function(int score)? _onGameEnd;

  void attachEndCallback(void Function(int score) cb) {
    _onGameEnd = cb;
  }

  // ---------------------------------------------------------------------
  // Lifecycle — matches the GameModule contract.
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

  /// True once the game has ended (no more legal placements). The host
  /// uses this to guard against double-push to the rewards screen.
  bool get hasEnded => _state.isEnded;

  // ---------------------------------------------------------------------
  // Public accessors for the widget tree.
  // ---------------------------------------------------------------------

  BoardGrid get board => _state.board;
  List<BlockPiece> get tray => _state.tray;
  int get score => _state.score;
  bool get isPaused => _state.isPaused;
  List<int> get flashingRows => _flashingRows;
  List<int> get flashingCols => _flashingCols;
  bool isFlashing(int r, int c) =>
      _flashingRows.contains(r) || _flashingCols.contains(c);

  /// Color key for a placed cell — uses the piece id so cells from the
  /// same piece share a color. `null` for empty cells.
  String? pieceIdAt(int r, int c) => _state.board.getCell(r, c);

  // ---------------------------------------------------------------------
  // Player input — drag-and-drop.
  // ---------------------------------------------------------------------

  /// The player picked up a piece from the tray. Record which one so a
  /// subsequent [hoverAt] / [dropAt] can resolve the move.
  void beginDrag(int pieceIndex) {
    if (_state.isPaused || _state.isEnded) return;
    if (pieceIndex < 0 || pieceIndex >= _state.tray.length) return;
    _hoverPieceIndex = <int>[pieceIndex];
    notifyListeners();
  }

  void cancelDrag() {
    _hoverPieceIndex = null;
    _hoverAt = null;
    notifyListeners();
  }

  /// Update the hover preview as the player drags the piece over the
  /// grid. (row, col) is the top-left cell of the piece's bounding box.
  void hoverAt(int topRow, int leftCol) {
    if (_state.isPaused || _state.isEnded) return;
    final idx = _hoverPieceIndex;
    if (idx == null) return;
    final piece = _state.tray[idx[0]];
    final maxR = logic.boardSize - piece.height;
    final maxC = logic.boardSize - piece.width;
    final clamped = <int>[
      topRow.clamp(0, maxR),
      leftCol.clamp(0, maxC),
    ];
    if (_hoverAt == null || _hoverAt![0] != clamped[0] || _hoverAt![1] != clamped[1]) {
      _hoverAt = clamped;
      notifyListeners();
    }
  }

  /// True if the currently-hovered piece would overlap / fall off the
  /// board at its current hover position. Used by the widget to color
  /// the preview red.
  bool get isHoverInvalid {
    final idx = _hoverPieceIndex;
    final at = _hoverAt;
    if (idx == null || at == null) return false;
    final piece = _state.tray[idx[0]];
    for (final cell in piece.cells) {
      final r = at[0] + cell[0];
      final c = at[1] + cell[1];
      if (!_state.board.inBounds(r, c)) return true;
      if (_state.board.isFilled(r, c)) return true;
    }
    return false;
  }

  /// Drop a piece from the tray at (topRow, leftCol). Called by the
  /// grid's [DragTarget] when the player releases a drag. If the move
  /// is valid, commit and refill the tray. If invalid, no-op (the
  /// widget shows a red preview to telegraph this).
  void dropAt(int pieceIndex, int topRow, int leftCol) {
    if (_state.isPaused || _state.isEnded) return;
    if (pieceIndex < 0 || pieceIndex >= _state.tray.length) return;
    final piece = _state.tray[pieceIndex];
    final step = logic.placePiece(
      board: _state.board,
      piece: piece,
      topRow: topRow,
      leftCol: leftCol,
    );
    if (step == null) {
      notifyListeners();
      return;
    }

    // Build the new tray: refill the consumed slot.
    final newTray = List<BlockPiece>.from(_state.tray)
      ..removeAt(pieceIndex)
      ..add(logic.drawPiece());

    // Score: 1 per cell placed + bonus per line cleared.
    final lineScore = _lineScore(step.linesCleared);
    final placementScore = step.cellsPlaced;
    final totalScore = placementScore + lineScore;

    _state = _state.copyWith(
      board: step.board,
      tray: newTray,
      score: _state.score + totalScore,
    );

    // Trigger the line-clear flash for the renderer.
    _flashingRows = step.clearedRows;
    _flashingCols = step.clearedCols;
    _flashFramesLeft = step.clearedRows.isEmpty && step.clearedCols.isEmpty
        ? 0
        : 8;

    // Game over?
    if (logic.isGameOver(_state.board, _state.tray)) {
      _state = _state.copyWith(isEnded: true);
      _ticker.stop();
      notifyListeners();
      _onGameEnd?.call(_state.score);
      return;
    }

    notifyListeners();
  }

  /// Drop the currently-dragged piece. Kept for backwards compatibility
  /// with the [beginDrag]/[hoverAt]/[drop] legacy API. Prefer [dropAt].
  void drop() {
    final idx = _hoverPieceIndex;
    final at = _hoverAt;
    _hoverPieceIndex = null;
    _hoverAt = null;
    if (idx == null || at == null) {
      notifyListeners();
      return;
    }
    dropAt(idx[0], at[0], at[1]);
  }

  /// Per-line bonus to reward multi-line clears.
  static int _lineScore(int lines) {
    if (lines <= 0) return 0;
    // 10 per line, +5 bonus for each line beyond the first.
    return 10 * lines + 5 * (lines - 1).clamp(0, 99);
  }

  // ---------------------------------------------------------------------
  // Tick — drives the line-clear flash.
  // ---------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    if (_state.isPaused || _state.isEnded) return;
    if (_flashFramesLeft > 0) {
      _flashFramesLeft--;
      if (_flashFramesLeft == 0) {
        _flashingRows = const [];
        _flashingCols = const [];
      }
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Cleanup.
  // ---------------------------------------------------------------------

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Mutable bag used by the controller. Copy-on-write.
class _State {
  _State({
    required this.board,
    required this.tray,
    required this.score,
    required this.isPaused,
    required this.isEnded,
  });

  factory _State.initial(BlockPuzzleLogic logic) {
    return _State(
      board: BoardGrid(logic.boardSize),
      tray: logic.initialTray(),
      score: 0,
      isPaused: false,
      isEnded: false,
    );
  }

  final BoardGrid board;
  final List<BlockPiece> tray;
  final int score;
  final bool isPaused;
  final bool isEnded;

  _State copyWith({
    BoardGrid? board,
    List<BlockPiece>? tray,
    int? score,
    bool? isPaused,
    bool? isEnded,
  }) {
    return _State(
      board: board ?? this.board,
      tray: tray ?? this.tray,
      score: score ?? this.score,
      isPaused: isPaused ?? this.isPaused,
      isEnded: isEnded ?? this.isEnded,
    );
  }
}
