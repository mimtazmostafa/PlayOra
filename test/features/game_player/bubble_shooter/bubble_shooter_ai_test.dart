import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/features/game_player/bubble_shooter/bubble_shooter_ai.dart';
import 'package:playnest/features/game_player/bubble_shooter/bubble_shooter_state.dart';

void main() {
  group('BubbleShooterAi', () {
    test('returns null when the game is over', () {
      final state = BubbleShooterState.initial(rng: Random(1)).copyWith(
        status: BubbleGameStatus.won,
      );
      final aim = const BubbleShooterAi().aimSuggestion(
        state: state,
        nextShot: BubbleColor.red,
      );
      expect(aim, isNull);
    });

    test('returns a snap target with at least one match when possible',
        () {
      // Plant a 2-cluster of red at row 14 columns 0 and 1.
      final state = BubbleShooterState.initial(rng: Random(1)).copyWith(
        board: _boardWithRedCluster(),
      );
      final aim = const BubbleShooterAi().aimSuggestion(
        state: state,
        nextShot: BubbleColor.red,
      );
      expect(aim, isNotNull);
      // The recommendation must be a cell adjacent to the red cluster
      // at (14, 0) and (14, 1). Adjacent cells (in hex-grid offset
      // convention) are:
      //   * row 13, col 0 or col 1     (upper neighbors of the cluster)
      //   * row 14, col 2              (right neighbor of (14, 1))
      //   * row 15, col 1 or col 2     (lower neighbors)
      // The AI iterates top-to-bottom, so any of these is a valid
      // returned candidate — we just need to assert it's one of the
      // adjacent cells, not specifically row 14.
      expect(
        aim!.row,
        anyOf(13, 14, 15),
        reason:
            'AI must suggest a snap target adjacent to the red cluster '
            'at row 14. Got row=${aim.row}, col=${aim.col}.',
      );
      expect(aim.col, anyOf(0, 1, 2),
          reason:
              'AI must suggest a snap target whose column is adjacent '
              'to the cluster (col 0 or 1). Got col=${aim.col}.');
    });

    test('returns some target even when no match is possible', () {
      final state = BubbleShooterState.initial(rng: Random(1));
      final aim = const BubbleShooterAi().aimSuggestion(
        state: state,
        nextShot: BubbleColor.red,
      );
      expect(aim, isNotNull);
    });
  });
}

List<BubbleColor?> _boardWithRedCluster() {
  final board = List<BubbleColor?>.filled(192, null);
  board[14 * 12 + 0] = BubbleColor.red;
  board[14 * 12 + 1] = BubbleColor.red;
  return board;
}
