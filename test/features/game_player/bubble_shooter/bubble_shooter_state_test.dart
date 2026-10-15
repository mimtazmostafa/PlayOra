import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/features/game_player/bubble_shooter/bubble_shooter_state.dart';

void main() {
  group('BubbleShooterState', () {
    test('initial state fills the top 5 rows with random colors', () {
      final state = BubbleShooterState.initial(rng: Random(42));
      expect(state.filledCount, greaterThan(0));
      expect(state.score, 0);
      expect(state.status, BubbleGameStatus.ongoing);
    });

    test('shoot into an empty cell puts a bubble there', () {
      final state = BubbleShooterState.initial(rng: Random(42));
      final updated = state.shoot(
        row: 14,
        col: 5,
        shot: BubbleColor.red,
        rng: Random(42),
      );
      expect(updated.at(14, 5), BubbleColor.red);
    });

    test('match-3 cluster of same color pops the whole cluster', () {
      // Build a board with 3 red bubbles in a row at row 14.
      final state = _boardWithRow([
        // Even row — 12 columns
        ...List<BubbleColor?>.filled(12, null),
        // Skip row 13..14 cells, fill row 14 cols 5,6,7 with red.
      ]);
      final board = List<BubbleColor?>.from(state.board);
      board[14 * 12 + 4] = BubbleColor.red;
      board[14 * 12 + 5] = BubbleColor.red;
      board[14 * 12 + 6] = BubbleColor.red;
      final seeded = state.copyWith(board: board);
      final updated = seeded.shoot(
        row: 14,
        col: 7,
        shot: BubbleColor.red,
        rng: Random(1),
      );
      // All four reds should pop.
      expect(updated.at(14, 4), isNull);
      expect(updated.at(14, 5), isNull);
      expect(updated.at(14, 6), isNull);
      expect(updated.at(14, 7), isNull);
      expect(updated.score, 4);
    });

    test('orphans drop after a chain pop', () {
      // Build a setup where popping the ceiling support causes a lower
      // red bubble to drop.
      //
      // Hex grid (offset rows): even rows have direct left/right
      // neighbors at col-1/col+1. Odd rows are shifted half a cell,
      // so their left/right same-row neighbors are col-1 and col+2
      // (NOT col+1). To make a horizontal 3-cluster plus a hanging
      // orphan, we use an even row so the geometry is straightforward.
      final board = List<BubbleColor?>.filled(192, null);
      // Even row 4 cells 0,1 — both red. Same-row neighbors in an
      // even row (left=col-1, right=col+1), so (4,0)-(4,1) are
      // adjacent. We'll add a third red at (4, 2) to form a
      // 3-cluster.
      board[4 * 12 + 0] = BubbleColor.red;
      board[4 * 12 + 1] = BubbleColor.red;
      // Row 5 cell 0 — isolated red hanging from row 4 col 0.
      // Row 5 is odd, so (5, 0)'s upper neighbors are (4, 0) and
      // (4, 1); lower-left/uppers into (4, 0) give it support.
      board[5 * 12 + 0] = BubbleColor.red;
      final state = BubbleShooterState.initial(rng: Random(1)).copyWith(
        board: board,
      );
      // Shoot (4, 2) red → pops (4, 0), (4, 1), (4, 2). The (5, 0)
      // bubble only had support from (4, 0) — now popped — so it
      // becomes an orphan and is dropped to null.
      final updated = state.shoot(
        row: 4,
        col: 2,
        shot: BubbleColor.red,
        rng: Random(1),
      );
      expect(updated.at(5, 0), isNull,
          reason: '(5,0) had support only from (4,0); after the pop '
              'chain, the orphan-drop pass should clear it.');
    });

    test('a bubble at the ceiling line triggers a loss', () {
      final board = List<BubbleColor?>.filled(192, null);
      board[5 * 12 + 6] = BubbleColor.red;
      final state = BubbleShooterState.initial(rng: Random(1)).copyWith(
        board: board,
      );
      expect(state.status, BubbleGameStatus.ongoing);
      final updated = state.shoot(
        row: 5,
        col: 7,
        shot: BubbleColor.red,
        rng: Random(1),
      );
      expect(updated.status, BubbleGameStatus.lost);
    });

    test('reaching the score target triggers a win', () {
      final state = BubbleShooterState.initial(rng: Random(1))
          .copyWith(score: 998);
      final board = List<BubbleColor?>.from(state.board);
      // Plant a guaranteed match-3 row.
      board[14 * 12 + 4] = BubbleColor.red;
      board[14 * 12 + 5] = BubbleColor.red;
      final updated = state.copyWith(board: board).shoot(
        row: 14,
        col: 6,
        shot: BubbleColor.red,
        rng: Random(1),
      );
      expect(updated.score, greaterThanOrEqualTo(1000));
      expect(updated.status, BubbleGameStatus.won);
    });

    test('highestFilledRow returns -1 for empty board', () {
      final state = BubbleShooterState.initial(
        rng: Random(1),
        startRows: 0,
      );
      expect(state.highestFilledRow, -1);
    });

    test('shotsTaken increments on every successful shot', () {
      final state = BubbleShooterState.initial(rng: Random(1));
      final updated = state.shoot(
        row: 14,
        col: 11,
        shot: BubbleColor.blue,
        rng: Random(1),
      );
      expect(updated.shotsTaken, 1);
    });
  });
}

BubbleShooterState _boardWithRow(List<BubbleColor?> firstRow) {
  final board = List<BubbleColor?>.filled(192, null);
  for (var c = 0; c < firstRow.length && c < 12; c++) {
    board[c] = firstRow[c];
  }
  return BubbleShooterState.initial(rng: Random(1)).copyWith(board: board);
}
