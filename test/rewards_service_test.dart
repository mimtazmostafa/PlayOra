import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/repositories/rewards_repository.dart';
import 'package:playnest/features/rewards/rewards_controller.dart';
import 'package:playnest/features/rewards/rewards_model.dart';

void main() {
  group('RewardsCurve.levelFor', () {
    const curve = RewardsCurve();

    test('returns 1 for 0 xp', () {
      expect(curve.levelFor(0), 1);
    });

    test('returns 1 just below the level-2 threshold', () {
      expect(curve.levelFor(49), 1);
    });

    test('returns 2 exactly at the level-2 threshold', () {
      expect(curve.levelFor(50), 2);
    });

    test('returns 2 just below the level-3 threshold', () {
      expect(curve.levelFor(199), 2);
    });

    test('returns 3 at the level-3 threshold', () {
      expect(curve.levelFor(200), 3);
    });

    test('returns 4 at the level-4 threshold', () {
      expect(curve.levelFor(450), 4);
    });

    test('clamp negatives to level 1', () {
      expect(curve.levelFor(-100), 1);
    });
  });

  group('RewardsCurve.xpToReachLevel', () {
    const curve = RewardsCurve();

    test('returns 0 for level 1', () {
      expect(curve.xpToReachLevel(1), 0);
    });

    test('matches levelFor thresholds', () {
      expect(curve.xpToReachLevel(2), 50);
      expect(curve.xpToReachLevel(3), 200);
      expect(curve.xpToReachLevel(4), 450);
      expect(curve.xpToReachLevel(5), 800);
    });

    test('round-trips with levelFor', () {
      for (var l = 1; l <= 6; l++) {
        final xp = curve.xpToReachLevel(l);
        expect(curve.levelFor(xp), l,
            reason: 'level $l should round-trip at $xp xp');
      }
    });
  });

  group('RewardsCurve.xpToNextLevel', () {
    const curve = RewardsCurve();

    test('first level-up costs 50 xp', () {
      expect(curve.xpToNextLevel(1), 50);
    });

    test('consecutive gaps widen as level grows', () {
      // 1→2: 50, 2→3: 150, 3→4: 250, 4→5: 350, 5→6: 450
      expect(curve.xpToNextLevel(1), 50);
      expect(curve.xpToNextLevel(2), 150);
      expect(curve.xpToNextLevel(3), 250);
      expect(curve.xpToNextLevel(4), 350);
      expect(curve.xpToNextLevel(5), 450);
    });
  });

  group('RewardsCurve.progressFor', () {
    const curve = RewardsCurve();

    test('0 xp at level 1 is empty (no progress yet)', () {
      // 0 xp → still 0/50 progress, but the curve has nothing to show.
      expect(curve.progressFor(0, 1), 0.0);
    });

    test('halfway through the first level is 0.5', () {
      expect(curve.progressFor(25, 1), closeTo(0.5, 1e-9));
    });

    test('exactly at level-2 threshold starts level 2 at 0', () {
      // At 50 xp you have just *reached* level 2 — no progress yet into it.
      expect(curve.progressFor(50, 2), 0.0);
    });

    test('halfway through level 2 is 0.5', () {
      // 50 xp to reach L2, 150 to L3; midpoint = 50 + 75 = 125 xp.
      expect(curve.progressFor(125, 2), closeTo(0.5, 1e-9));
    });

    test('clamps beyond the threshold', () {
      expect(curve.progressFor(60, 1), 1.0);
    });
  });

  group('RewardsSnapshot', () {
    test('empty snapshot is (0, 0)', () {
      expect(RewardsSnapshot.empty.coins, 0);
      expect(RewardsSnapshot.empty.xp, 0);
    });

    test('withCoins / withXp are non-mutating', () {
      const before = RewardsSnapshot(coins: 10, xp: 100);
      final a = before.withCoins(5);
      final b = before.withXp(50);
      expect(a, const RewardsSnapshot(coins: 15, xp: 100));
      expect(b, const RewardsSnapshot(coins: 10, xp: 150));
      expect(before, const RewardsSnapshot(coins: 10, xp: 100));
    });

    test('value equality', () {
      expect(
        const RewardsSnapshot(coins: 1, xp: 2),
        const RewardsSnapshot(coins: 1, xp: 2),
      );
      expect(
        const RewardsSnapshot(coins: 1, xp: 2).hashCode,
        const RewardsSnapshot(coins: 1, xp: 2).hashCode,
      );
    });
  });

  group('LevelDelta', () {
    test('no level crossing → didLevelUp false, newLevels empty', () {
      const d = LevelDelta(beforeLevel: 3, afterLevel: 3);
      expect(d.didLevelUp, isFalse);
      expect(d.newLevels, isEmpty);
    });

    test('single-level crossing yields one entry', () {
      const d = LevelDelta(beforeLevel: 3, afterLevel: 4);
      expect(d.didLevelUp, isTrue);
      expect(d.newLevels, [4]);
    });

    test('multi-level crossing yields each level', () {
      const d = LevelDelta(beforeLevel: 3, afterLevel: 6);
      expect(d.newLevels, [4, 5, 6]);
    });
  });

  group('InMemoryRewardsRepository', () {
    test('starts empty', () async {
      final repo = InMemoryRewardsRepository();
      expect(await repo.read(), RewardsSnapshot.empty);
    });

    test('round-trips a snapshot', () async {
      final repo = InMemoryRewardsRepository();
      const s = RewardsSnapshot(coins: 42, xp: 1000);
      await repo.write(s);
      expect(await repo.read(), s);
    });
  });

  group('RewardsController', () {
    late ProviderContainer container;
    late InMemoryRewardsRepository repo;
    late List<int> streamEvents;

    setUp(() {
      repo = InMemoryRewardsRepository();
      streamEvents = [];
      container = ProviderContainer(
        overrides: [
          rewardsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      // Subscribe to the broadcast stream.
      container.read(rewardsControllerProvider.notifier).levelUpStream
          .listen(streamEvents.add);
    });

    tearDown(() {
      container.read(rewardsControllerProvider.notifier).dispose();
      container.dispose();
    });

    test('starts at empty snapshot', () {
      expect(container.read(rewardsControllerProvider), RewardsSnapshot.empty);
    });

    test('addCoins updates state and persists', () async {
      await container.read(rewardsControllerProvider.notifier).addCoins(50);
      expect(container.read(rewardsControllerProvider).coins, 50);
      expect((await repo.read()).coins, 50);
    });

    test('addCoins clamps negatives to zero (no negative balance)', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      await c.addCoins(10);
      await c.addCoins(-100);
      expect(container.read(rewardsControllerProvider).coins, 0);
    });

    test('addXp updates state and persists', () async {
      await container.read(rewardsControllerProvider.notifier).addXp(120);
      expect(container.read(rewardsControllerProvider).xp, 120);
      expect((await repo.read()).xp, 120);
    });

    test('addXp ignores non-positive deltas', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      await c.addXp(0);
      await c.addXp(-50);
      expect(container.read(rewardsControllerProvider).xp, 0);
    });

    test('awardForScore: 1000 → 100 coins + 200 xp', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      final delta = await c.awardForScore(1000);
      expect(container.read(rewardsControllerProvider).coins, 100);
      expect(container.read(rewardsControllerProvider).xp, 200);
      // 200 xp crosses level 1 → 3.
      expect(delta.beforeLevel, 1);
      expect(delta.afterLevel, 3);
      expect(delta.didLevelUp, isTrue);
    });

    test('awardForScore: 0 is a no-op', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      final delta = await c.awardForScore(0);
      expect(container.read(rewardsControllerProvider), RewardsSnapshot.empty);
      expect(delta.didLevelUp, isFalse);
    });

    test('levelUpStream fires for each crossed level', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      // 5000 score → 500 coins + 1000 xp. With the curve that crosses
      // level 1 → 5 (since xp 1000 ≈ level 5 at 800 threshold).
      await c.awardForScore(5000);
      // Allow microtasks for the broadcast stream to flush.
      await Future<void>.delayed(Duration.zero);
      expect(streamEvents, [2, 3, 4, 5]);
    });

    test('multiple awards stack and persist', () async {
      final c = container.read(rewardsControllerProvider.notifier);
      await c.awardForScore(100); // +10 coins, +20 xp
      await c.awardForScore(200); // +20 coins, +40 xp
      expect(container.read(rewardsControllerProvider).coins, 30);
      expect(container.read(rewardsControllerProvider).xp, 60);
      // The repo reflects the latest write, not the intermediate.
      expect((await repo.read()).coins, 30);
      expect((await repo.read()).xp, 60);
    });
  });
}