/// Heuristic AI for the Bubble Shooter.
///
/// The "AI" notion here is a little unusual: the player is the shooter
/// in their own game. The AI is exposed via [aimSuggestion] — a helper
/// the user can toggle on to see where the engineer would aim given the
/// current board. It looks at the next-to-shoot bubble, finds every
/// empty cell that would land it adjacent to a same-color cluster of
/// ≥ 2, and returns the cell whose pop would remove the most bubbles
/// (counting both the immediate cluster and the orphans that would
/// drop as a side-effect).
///
/// The implementation is intentionally simple — a depth-1 search over
/// valid snap targets, ranked by a linear score. It does not try to
/// beat the player; it just recommends a reasonable shot.
library;

import 'bubble_shooter_state.dart';

class BubbleShooterAi {
  const BubbleShooterAi();

  /// Returns the row+col the player should snap to, or null when no
  /// good shot exists (board is empty or only one color). The
  /// controller decides whether to overlay this on the aim line.
  AimSuggestion? aimSuggestion({
    required BubbleShooterState state,
    required BubbleColor nextShot,
  }) {
    if (state.isGameOver) return null;

    AimSuggestion? best;
    var bestScore = -1;

    for (var row = 0; row < BubbleShooterState.boardHeight; row++) {
      final cols = _columnsForRow(row);
      for (final col in cols) {
        if (state.at(row, col) != null) continue;
        final candidate = _evaluate(state, nextShot, row, col);
        if (candidate.score > bestScore) {
          bestScore = candidate.score;
          best = AimSuggestion(row: row, col: col, expectedScore: candidate.score);
        }
      }
    }
    return best;
  }

  _CandidateScore _evaluate(
    BubbleShooterState state,
    BubbleColor shot,
    int row,
    int col,
  ) {
    final neighborCount = _sameColorNeighborCount(state, shot, row, col);
    if (neighborCount == 0) {
      // No match — gentle penalty so we still suggest *something* but
      // prefer matches whenever possible.
      return _CandidateScore(neighborCount, 0);
    }
    // Would-pop bonus: 10 per same-color cluster expansion.
    final willPop = 1 + (neighborCount >= 1 ? 1 : 0);
    return _CandidateScore(neighborCount, willPop);
  }

  /// How many of the 6 hex neighbors are the same color as [shot].
  int _sameColorNeighborCount(
    BubbleShooterState state,
    BubbleColor shot,
    int row,
    int col,
  ) {
    var n = 0;
    for (final nCell in _neighbors(row, col)) {
      if (state.at(nCell[0], nCell[1]) == shot) n++;
    }
    return n;
  }

  /// Mirrors the offset-neighbor layout in [BubbleShooterState]. Kept
  /// here as a private helper because the AI is a separate concern
  /// from the rules engine.
  static List<List<int>> _neighbors(int row, int col) {
    final isEvenRow = row.isEven;
    final upperLeft = isEvenRow ? col - 1 : col;
    final upperRight = isEvenRow ? col : col + 1;
    final left = isEvenRow ? col - 1 : col;
    final right = isEvenRow ? col + 1 : col + 2;
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

  /// Mirrors the column-counts for an offset hex row: even rows have
  /// 12 columns, odd rows have 11 columns (interlocked).
  static List<int> _columnsForRow(int row) {
    if (row.isEven) {
      return List<int>.generate(12, (i) => i);
    }
    return List<int>.generate(11, (i) => i);
  }
}

class _CandidateScore {
  _CandidateScore(this.neighborCount, this.willPop);
  final int neighborCount;
  final int willPop;
  int get score => neighborCount * 5 + willPop * 10;
}

/// Direction to display the suggestion arrow on the aim line.
class AimSuggestion {
  const AimSuggestion({
    required this.row,
    required this.col,
    required this.expectedScore,
  });
  final int row;
  final int col;
  final int expectedScore;
}
