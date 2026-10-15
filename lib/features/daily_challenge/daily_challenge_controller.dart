import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_model.dart';
import '../../data/repositories/daily_challenge_repository.dart';
import '../games/games_providers.dart';
import 'daily_challenge_model.dart';

/// The "did the user just complete the daily challenge?" payload.
/// Emitted once per [recordCompletion] call when the score crosses the
/// target *and* the day wasn't already marked complete.
class DailyChallengeWin {
  const DailyChallengeWin({
    required this.gameId,
    required this.score,
    required this.target,
  });

  final String gameId;
  final int score;
  final int target;
}

/// Reactive daily-challenge state + persistence boundary.
///
/// Owns a [DailyChallenge] for *today* (device-local) and writes any
/// progress to the repository. The picker math is deterministic, so
/// the controller only needs to persist the user's best score +
/// completion flag — the rest is computed on every read.
class DailyChallengeController extends Notifier<DailyChallenge?> {
  late DailyChallengeRepository _repo;
  final DailyChallengeMath _math = const DailyChallengeMath();
  final StreamController<DailyChallengeWin> _winController =
      StreamController<DailyChallengeWin>.broadcast();

  /// Emitted exactly once per day when [recordCompletion] crosses
  /// the target for the first time. UI listens to trigger a
  /// distinct celebration.
  Stream<DailyChallengeWin> get completedStream => _winController.stream;

  @override
  DailyChallenge? build() {
    _repo = ref.read(dailyChallengeRepositoryProvider);
    ref.onDispose(() {
      if (!_winController.isClosed) {
        _winController.close();
      }
    });
    // Watch the games list so the controller rebuilds as soon as
    // the catalog finishes loading. Without this, the controller
    // would snapshot a null catalog at startup and stay empty.
    final games = ref.watch(gamesProvider).valueOrNull;
    return _compute(games);
  }

  /// Recompute today's challenge from the picker math + persisted
  /// progress. Cheap and side-effect free.
  DailyChallenge? _compute(List<Game>? games) {
    if (games == null || games.isEmpty) return null;

    final catalogIds = games.map((g) => g.id).toList(growable: false);
    final now = DateTime.now();
    final key = _math.dayKey(now);
    final gameId = _math.pickGameId(now, catalogIds);
    if (gameId == null) return null;

    final target = _math.targetFor(gameId, now);
    final saved = _repo.load(key);

    return DailyChallenge(
      dayKey: key,
      gameId: gameId,
      targetScore: target,
      bestScore: saved?.bestScore ?? 0,
      isCompleted: saved?.isCompleted ?? false,
    );
  }

  /// Re-read today's record from the repository without changing it.
  /// Useful when games finish loading after the controller was built.
  void refresh() {
    final next = _compute(ref.read(gamesProvider).valueOrNull);
    if (next != state) state = next;
  }

  /// Record the user's [score] on [gameId]. Returns the resulting
  /// challenge (with updated best / completion). When [gameId] is
  /// today's challenge game and the score crosses the target for the
  /// first time today, also emits on [completedStream].
  ///
  /// Calling this on a non-challenge game or with a low score is a
  /// no-op for the *challenge* but does not error.
  Future<DailyChallenge?> recordCompletion({
    required String gameId,
    required int score,
  }) async {
    final current = state;
    if (current == null) return null;

    // Only the featured game counts. Other games don't move the needle.
    if (current.gameId != gameId) return current;

    final newBest = score > current.bestScore ? score : current.bestScore;
    final crossedTarget =
        !current.isCompleted && newBest >= current.targetScore;

    if (newBest == current.bestScore && !crossedTarget) {
      return current; // nothing changed
    }

    final updated = current.withCompleted(
      value: current.isCompleted || crossedTarget,
      bestScore: newBest,
    );
    state = updated;

    await _repo.save(DailyChallengeRecord(
      dayKey: updated.dayKey,
      bestScore: updated.bestScore,
      isCompleted: updated.isCompleted,
    ));

    if (crossedTarget) {
      _winController.add(DailyChallengeWin(
        gameId: updated.gameId,
        score: newBest,
        target: updated.targetScore,
      ));
    }

    return updated;
  }
}

final dailyChallengeRepositoryProvider = Provider<DailyChallengeRepository>(
  (ref) {
    throw UnimplementedError(
      'dailyChallengeRepositoryProvider must be overridden in ProviderScope',
    );
  },
);

final dailyChallengeControllerProvider =
    NotifierProvider<DailyChallengeController, DailyChallenge?>(
  DailyChallengeController.new,
);

final dailyChallengeCompletedStreamProvider =
    StreamProvider<DailyChallengeWin>((ref) {
  final controller = ref.watch(dailyChallengeControllerProvider.notifier);
  return controller.completedStream;
});