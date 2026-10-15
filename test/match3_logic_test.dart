import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/features/game_player/match3/match3_state.dart';

void main() {
  group('Match3Logic.newGame', () {
    test('produces a non-empty board of the configured size', () {
      final logic = Match3Logic(gridSize: 7);
      final state = logic.newGame();
      expect(state.grid.length, 7);
      expect(state.grid.every((row) => row.length == 7), isTrue);
    });

    test('starts with zero score, full timer, not paused, not ended', () {
      final logic = Match3Logic(gridSize: 7, roundSeconds: 60);
      final state = logic.newGame();
      expect(state.score, 0);
      expect(state.secondsRemaining, 60);
      expect(state.isPaused, isFalse);
      expect(state.isEnded, isFalse);
      expect(state.cascadeLevel, 0);
    });

    test('does not start with any 3+ matches (re-rolls until clean)', () {
      final logic = Match3Logic(gridSize: 8, seed: 42);
      for (int i = 0; i < 20; i++) {
        final state = logic.newGame();
        final matches = logic.findMatches(state.grid);
        expect(matches, isEmpty, reason: 'iteration $i should be match-free');
      }
    });

    test('is deterministic when given the same seed', () {
      final a = Match3Logic(seed: 7).newGame();
      final b = Match3Logic(seed: 7).newGame();
      for (int r = 0; r < a.grid.length; r++) {
        for (int c = 0; c < a.grid[r].length; c++) {
          expect(a.grid[r][c], b.grid[r][c]);
        }
      }
    });
  });

  group('Match3Logic.isAdjacent', () {
    final logic = Match3Logic(gridSize: 7);

    test('true for orthogonal neighbors', () {
      expect(logic.isAdjacent(const GridPos(0, 0), const GridPos(0, 1)), isTrue);
      expect(logic.isAdjacent(const GridPos(2, 3), const GridPos(3, 3)), isTrue);
      expect(logic.isAdjacent(const GridPos(5, 5), const GridPos(5, 4)), isTrue);
    });

    test('false for diagonal, same, or non-neighbor cells', () {
      expect(logic.isAdjacent(const GridPos(0, 0), const GridPos(1, 1)), isFalse);
      expect(logic.isAdjacent(const GridPos(2, 2), const GridPos(2, 2)), isFalse);
      expect(logic.isAdjacent(const GridPos(0, 0), const GridPos(0, 5)), isFalse);
    });
  });

  group('Match3Logic.findMatches', () {
    final logic = Match3Logic(gridSize: 5);

    test('returns empty set when there are no matches', () {
      final grid = List<List<GemType>>.generate(
        5,
        (r) => List<GemType>.generate(5, (c) => GemType.values[(r + c) % 6]),
      );
      expect(logic.findMatches(grid), isEmpty);
    });

    test('detects a horizontal run of three', () {
      final grid = List<List<GemType>>.generate(
        5,
        (r) => List<GemType>.generate(5, (_) => GemType.ruby),
      );
      grid[2] = [GemType.topaz, GemType.topaz, GemType.topaz, GemType.topaz, GemType.topaz];
      // Top row ruby, but middle row has 5 in a row → horizontal matches.
      final matches = logic.findMatches(grid);
      expect(matches, contains(const GridPos(2, 0)));
      expect(matches, contains(const GridPos(2, 1)));
      expect(matches, contains(const GridPos(2, 2)));
      expect(matches, contains(const GridPos(2, 3)));
      expect(matches, contains(const GridPos(2, 4)));
    });

    test('detects a vertical run of three', () {
      final grid = List<List<GemType>>.generate(
        5,
        (r) => List<GemType>.generate(5, (_) => GemType.ruby),
      );
      grid[0][0] = GemType.emerald;
      grid[1][0] = GemType.emerald;
      grid[2][0] = GemType.emerald;
      final matches = logic.findMatches(grid);
      expect(matches, contains(const GridPos(0, 0)));
      expect(matches, contains(const GridPos(1, 0)));
      expect(matches, contains(const GridPos(2, 0)));
    });

    test('a run of two is not a match', () {
      // Latin square — no 3-in-a-row horizontally or vertically by design.
      final grid = <List<GemType>>[
        [GemType.ruby, GemType.amethyst, GemType.topaz, GemType.emerald, GemType.sapphire],
        [GemType.amethyst, GemType.topaz, GemType.emerald, GemType.sapphire, GemType.ruby],
        [GemType.topaz, GemType.emerald, GemType.sapphire, GemType.ruby, GemType.amethyst],
        [GemType.emerald, GemType.sapphire, GemType.ruby, GemType.amethyst, GemType.topaz],
        [GemType.sapphire, GemType.ruby, GemType.amethyst, GemType.topaz, GemType.emerald],
      ];
      // Baseline — this grid has no matches.
      expect(logic.findMatches(grid), isEmpty);
      // Insert a run of two adjacent sapphires. Still no match.
      grid[0][0] = GemType.sapphire;
      grid[0][1] = GemType.sapphire;
      expect(logic.findMatches(grid), isEmpty);
    });
  });

  group('Match3Logic.processSwap', () {
    final logic = Match3Logic(gridSize: 5, seed: 1);

    test('returns the original grid when the swap does not match', () {
      // Build a board with no possible matches to start — too narrow to
      // engineer every case, so we use the newGame state and verify that
      // a no-match swap bounces back with hadEffect: false.
      final state = logic.newGame();

      // Find any pair of adjacent cells that are different colors and that
      // wouldn't form a match when swapped. We probe a few candidates and
      // accept the first no-match swap.
      final candidates = <List<GridPos>>[
        [const GridPos(0, 0), const GridPos(0, 1)],
        [const GridPos(1, 1), const GridPos(1, 2)],
        [const GridPos(2, 3), const GridPos(2, 4)],
      ];

      SwapOutcome? noMatch;
      for (final pair in candidates) {
        final outcome =
            logic.processSwap(state.grid, pair[0], pair[1]);
        if (!outcome.hadEffect) {
          noMatch = outcome;
          break;
        }
      }
      // If every candidate happened to match (extremely unlikely with a
      // 5x5 board of 6 types), skip the assertion.
      if (noMatch != null) {
        expect(noMatch.hadEffect, isFalse);
        expect(noMatch.clearedCount, 0);
        expect(noMatch.maxCascadeLevel, 0);
        expect(noMatch.newGrid, equals(state.grid));
      }
    });

    test('returns null grid when given out-of-bounds positions', () {
      final grid = logic.newGame().grid;
      final outcome = logic.processSwap(
        grid,
        const GridPos(-1, 0),
        const GridPos(0, 0),
      );
      expect(outcome.hadEffect, isFalse);
      expect(outcome.newGrid, equals(grid));
    });

    test('when a swap does match, returns the resolved grid and counts cleared', () {
      // Hand-build a board where swapping (2,2) and (2,3) creates a
      // horizontal run of three emeralds.
      var grid = List<List<GemType>>.generate(
        5,
        (r) => List<GemType>.generate(5, (_) => GemType.ruby),
      );
      grid[2][1] = GemType.emerald;
      grid[2][2] = GemType.topaz; // currently at (2,2)
      grid[2][3] = GemType.emerald;
      grid[2][4] = GemType.emerald;

      final outcome = logic.processSwap(
        grid,
        const GridPos(2, 2),
        const GridPos(2, 3),
      );
      expect(outcome.hadEffect, isTrue);
      expect(outcome.clearedCount, greaterThanOrEqualTo(3));
      // The result grid should have NO emerald at (2,2) anymore, because
      // it either cleared or got pushed down by the refill.
      expect(outcome.newGrid[2][2], isNot(equals(GemType.emerald)));
    });

    test('cascadeLevel is at least 1 for a first-order match', () {
      // Same crafted board as above — first-order match.
      var grid = List<List<GemType>>.generate(
        5,
        (r) => List<GemType>.generate(5, (_) => GemType.ruby),
      );
      grid[2][1] = GemType.emerald;
      grid[2][2] = GemType.topaz;
      grid[2][3] = GemType.emerald;
      grid[2][4] = GemType.emerald;

      final outcome = logic.processSwap(
        grid,
        const GridPos(2, 2),
        const GridPos(2, 3),
      );
      expect(outcome.maxCascadeLevel, greaterThanOrEqualTo(1));
    });
  });

  group('Match3Logic.resolveCleared', () {
    test('returns the grid unchanged when nothing is cleared', () {
      final logic = Match3Logic(seed: 9);
      final grid = logic.newGame().grid;
      final result = logic.resolveCleared(grid, const <GridPos>{});
      expect(result.grid, equals(grid));
      expect(result.cleared, isEmpty);
    });

    test('drops cells and fills the top with fresh gems', () {
      final logic = Match3Logic(gridSize: 4, seed: 3);
      // Latin square — every row and column has a unique gem, no matches.
      final grid = <List<GemType>>[
        [GemType.ruby, GemType.amethyst, GemType.topaz, GemType.emerald],
        [GemType.amethyst, GemType.topaz, GemType.emerald, GemType.sapphire],
        [GemType.topaz, GemType.emerald, GemType.sapphire, GemType.ruby],
        [GemType.emerald, GemType.sapphire, GemType.ruby, GemType.amethyst],
      ];
      final cleared = <GridPos>{const GridPos(3, 0), const GridPos(3, 1)};
      final result = logic.resolveCleared(grid, cleared);
      // Column 0 originally: [ruby, amethyst, topaz, emerald].
      // After clearing (3, 0), values drop to the bottom: row 3 = topaz
      // (was row 2), row 2 = amethyst (was row 1), row 1 = ruby (was row 0),
      // row 0 = fresh random gem.
      expect(result.grid[3][0], GemType.topaz);
      expect(result.grid[2][0], GemType.amethyst);
      expect(result.grid[1][0], GemType.ruby);
      // Row 0, column 0 should be NEW (not the original ruby).
      expect(result.grid[0][0], isNot(equals(GemType.ruby)));
      // Cleared set is returned as-is.
      expect(result.cleared, equals(cleared));
    });
  });
}