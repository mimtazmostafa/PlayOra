import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/features/game_player/block_puzzle/block_puzzle_state.dart';

void main() {
  group('BlockPuzzleLogic', () {
    test('placePiece commits to a fresh board', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 1);
      final board = BoardGrid(10);
      final piece = logic.drawPiece();
      // Find a valid placement.
      final placements = logic.validPlacements(board, piece);
      expect(placements, isNotEmpty,
          reason: 'piece must fit on a fresh 10x10 board');
      final topLeft = placements.first;
      final step = logic.placePiece(
        board: board,
        piece: piece,
        topRow: topLeft[0],
        leftCol: topLeft[1],
      );
      expect(step, isNotNull);
      expect(step!.clearedRows, isEmpty);
      expect(step.clearedCols, isEmpty);
      expect(step.cellsPlaced, piece.cells.length);
    });

    test('placePiece returns null when out of bounds', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 2);
      final board = BoardGrid(10);
      // Force an out-of-bounds call by passing -1.
      final piece = logic.drawPiece();
      final step = logic.placePiece(
        board: board,
        piece: piece,
        topRow: -1,
        leftCol: 0,
      );
      expect(step, isNull);
    });

    test('placePiece returns null on collision', () {
      final logic = BlockPuzzleLogic(boardSize: 4, traySize: 3, seed: 3);
      final board = BoardGrid(4);
      // Manually fill (0,0) to force a collision if piece covers it.
      board.cells[0][0] = 'X';
      // Construct a 1x1 piece and try to place it on the filled cell.
      const piece = BlockPiece(
        id: 1,
        shapeIndex: 0,
        cells: [
          [0, 0],
        ],
      );
      final step = logic.placePiece(
        board: board,
        piece: piece,
        topRow: 0,
        leftCol: 0,
      );
      expect(step, isNull);
    });

    test('placePiece on full row triggers row clearance', () {
      final logic = BlockPuzzleLogic(boardSize: 4, traySize: 3, seed: 4);
      final board = BoardGrid(4);
      // Fill row 0 except (0,0).
      for (int c = 1; c < 4; c++) {
        board.cells[0][c] = 'X';
      }
      // 1x1 dot, place at (0,0) — completes row 0.
      const piece = BlockPiece(
        id: 7,
        shapeIndex: 0,
        cells: [
          [0, 0],
        ],
      );
      final step = logic.placePiece(
        board: board,
        piece: piece,
        topRow: 0,
        leftCol: 0,
      );
      expect(step, isNotNull);
      expect(step!.clearedRows, contains(0));
      expect(step.clearedCols, isEmpty);
      // Cleared row in the returned board should be all null.
      for (int c = 0; c < 4; c++) {
        expect(step.board.cells[0][c], isNull);
      }
      // Original board must not have been mutated.
      expect(board.cells[0][1], 'X');
    });

    test('placePiece that completes both a row and a column clears both',
        () {
      final logic = BlockPuzzleLogic(boardSize: 4, traySize: 3, seed: 5);
      final board = BoardGrid(4);
      // Fill row 0 except (0,0).
      for (int c = 1; c < 4; c++) {
        board.cells[0][c] = 'X';
      }
      // Fill col 0 except (0,0).
      for (int r = 1; r < 4; r++) {
        board.cells[r][0] = 'Y';
      }
      const piece = BlockPiece(
        id: 11,
        shapeIndex: 0,
        cells: [
          [0, 0],
        ],
      );
      final step = logic.placePiece(
        board: board,
        piece: piece,
        topRow: 0,
        leftCol: 0,
      );
      expect(step, isNotNull);
      expect(step!.clearedRows, contains(0));
      expect(step.clearedCols, contains(0));
    });

    test('canPlaceAnywhere is true on empty board', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 6);
      final board = BoardGrid(10);
      final piece = logic.drawPiece();
      expect(logic.canPlaceAnywhere(board, piece), isTrue);
    });

    test('canPlaceAnywhere is false when no shape can fit', () {
      // Use a tiny board and a piece larger than the board.
      final logic = BlockPuzzleLogic(boardSize: 2, traySize: 3, seed: 7);
      final board = BoardGrid(2);
      const huge = BlockPiece(
        id: 0,
        shapeIndex: 4, // 1x5 piece
        cells: [
          [0, 0],
          [0, 1],
          [0, 2],
          [0, 3],
          [0, 4],
        ],
      );
      expect(logic.canPlaceAnywhere(board, huge), isFalse);
    });

    test('isGameOver true when no tray piece can be placed', () {
      final logic = BlockPuzzleLogic(boardSize: 2, traySize: 3, seed: 8);
      final board = BoardGrid(2);
      // All tray pieces are huge 1x5 — can't fit on a 2x2 board.
      const huge = BlockPiece(
        id: 0,
        shapeIndex: 4,
        cells: [
          [0, 0],
          [0, 1],
          [0, 2],
          [0, 3],
          [0, 4],
        ],
      );
      final tray = [huge, huge, huge];
      expect(logic.isGameOver(board, tray), isTrue);
    });

    test('isGameOver false when at least one tray piece can be placed', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 9);
      final board = BoardGrid(10);
      final tray = logic.initialTray();
      expect(logic.isGameOver(board, tray), isFalse);
    });

    test('drawPiece returns a valid non-null piece', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 10);
      final piece = logic.drawPiece();
      expect(piece.cells, isNotEmpty);
      expect(piece.width, greaterThan(0));
      expect(piece.height, greaterThan(0));
      expect(piece.shapeIndex, inInclusiveRange(0, BlockShapes.all.length - 1));
    });

    test('initialTray produces traySize pieces', () {
      final logic = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 11);
      final tray = logic.initialTray();
      expect(tray, hasLength(3));
      // Each piece should reference a known shape.
      for (final piece in tray) {
        expect(piece.shapeIndex, inInclusiveRange(0, 4));
      }
    });

    test('drawPiece is deterministic with the same seed', () {
      final a = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 42);
      final b = BlockPuzzleLogic(boardSize: 10, traySize: 3, seed: 42);
      final pa = a.drawPiece();
      final pb = b.drawPiece();
      expect(pa.shapeIndex, pb.shapeIndex);
      expect(pa.id, pb.id);
    });
  });

  group('BoardGrid', () {
    test('copy produces an independent deep copy', () {
      final board = BoardGrid(3);
      board.cells[0][0] = 'X';
      final copy = board.copy();
      copy.cells[1][1] = 'Y';
      expect(board.cells[1][1], isNull);
      expect(copy.cells[0][0], 'X');
      expect(copy.cells[1][1], 'Y');
    });

    test('inBounds respects size', () {
      final board = BoardGrid(3);
      expect(board.inBounds(0, 0), isTrue);
      expect(board.inBounds(2, 2), isTrue);
      expect(board.inBounds(-1, 0), isFalse);
      expect(board.inBounds(0, 3), isFalse);
      expect(board.inBounds(3, 0), isFalse);
    });
  });

  group('BlockPiece', () {
    test('width and height reflect the bounding box', () {
      const piece = BlockPiece(
        id: 0,
        shapeIndex: 2,
        cells: [
          [0, 0],
          [0, 1],
          [0, 2],
        ],
      );
      expect(piece.width, 3);
      expect(piece.height, 1);
    });
  });
}