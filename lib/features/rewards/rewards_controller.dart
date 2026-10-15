import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/rewards_repository.dart';
import 'rewards_model.dart';

/// Reactive rewards state + persistence boundary.
///
/// Holds a [RewardsSnapshot] in memory and writes every change to the
/// repository. Exposes [addCoins], [addXp], and [awardForScore] for
/// gameplay hooks. When xp crosses a level boundary, every crossed
/// level is emitted on [levelUpStream] so the UI can celebrate.
class RewardsController extends Notifier<RewardsSnapshot> {
  late RewardsRepository _repo;
  final StreamController<int> _levelUpController =
      StreamController<int>.broadcast();

  /// One event per level crossed. Listeners can render a burst per
  /// level when a single play crosses multiple levels.
  Stream<int> get levelUpStream => _levelUpController.stream;

  @override
  RewardsSnapshot build() {
    _repo = ref.read(rewardsRepositoryProvider);
    // Synchronous initial state. The repository is expected to be
    // in-memory by the time `build` runs (see `main.dart`, where we
    // `await` Hive before `runApp`). Tests can `seed()` the in-memory
    // repo before constructing the controller.
    return RewardsSnapshot.empty;
  }

  /// Adds [delta] coins. Negative deltas clamp the balance at 0 —
  /// we don't have a spending mechanic yet, but the UI may display
  /// affordances that subtract.
  Future<void> addCoins(int delta) async {
    final before = state;
    final nextCoins =
        delta < 0 && state.coins + delta < 0 ? 0 : state.coins + delta;
    final next = RewardsSnapshot(coins: nextCoins, xp: state.xp);
    await _commit(before, next);
  }

  /// Adds [delta] XP. Negative deltas are ignored — XP only grows.
  Future<void> addXp(int delta) async {
    if (delta <= 0) return;
    final before = state;
    final next = RewardsSnapshot(coins: state.coins, xp: state.xp + delta);
    await _commit(before, next);
  }

  /// The hook called by gameplay: awards coins + XP derived from
  /// [score]. Returns the [LevelDelta] so the caller can show the
  /// celebration immediately, in addition to the async events on
  /// [levelUpStream].
  Future<LevelDelta> awardForScore(int score) async {
    if (score <= 0) {
      return const LevelDelta(beforeLevel: 1, afterLevel: 1);
    }
    final before = state;
    final coins = score ~/ 10;
    final xp = score ~/ 5;
    final next = before.withCoins(coins).withXp(xp);
    await _commit(before, next);
    return LevelDelta(
      beforeLevel: const RewardsCurve().levelFor(before.xp),
      afterLevel: const RewardsCurve().levelFor(next.xp),
    );
  }

  Future<void> _commit(RewardsSnapshot before, RewardsSnapshot next) async {
    state = next;
    await _repo.write(next);
    const curve = RewardsCurve();
    final beforeLevel = curve.levelFor(before.xp);
    final afterLevel = curve.levelFor(next.xp);
    for (var l = beforeLevel + 1; l <= afterLevel; l++) {
      _levelUpController.add(l);
    }
  }

  /// Closes the broadcast stream. Call from app shutdown or tests.
  void dispose() {
    _levelUpController.close();
  }
}

/// Repository provider — overridden in `main.dart` with the Hive impl.
final rewardsRepositoryProvider = Provider<RewardsRepository>((ref) {
  throw UnimplementedError(
    'rewardsRepositoryProvider must be overridden in ProviderScope',
  );
});

final rewardsControllerProvider =
    NotifierProvider<RewardsController, RewardsSnapshot>(
  RewardsController.new,
);

/// Convenience: live stream of level-up events. UI overlays watch this.
///
/// We expose the controller's broadcast stream directly so multiple
/// listeners can attach independently without Riverpod resubscribing
/// on every state change.
final levelUpStreamProvider = StreamProvider<int>((ref) {
  final controller = ref.watch(rewardsControllerProvider.notifier);
  return controller.levelUpStream;
});