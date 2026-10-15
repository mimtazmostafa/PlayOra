import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/repositories/streak_repository.dart';
import 'package:playnest/features/streak/streak_controller.dart';
import 'package:playnest/features/streak/streak_model.dart';

void main() {
  group('StreakSnapshot', () {
    test('empty snapshot is (0, null)', () {
      expect(StreakSnapshot.empty.count, 0);
      expect(StreakSnapshot.empty.lastPlayDay, isNull);
      expect(StreakSnapshot.empty.isEmpty, isTrue);
    });

    test('isEmpty flips to false once count > 0', () {
      final s = StreakSnapshot(
        count: 1,
        lastPlayDay: DateTime(2024, 1, 1),
      );
      expect(s.isEmpty, isFalse);
    });

    test('value equality', () {
      final a = StreakSnapshot(count: 3, lastPlayDay: DateTime(2024, 1, 3));
      final b = StreakSnapshot(count: 3, lastPlayDay: DateTime(2024, 1, 3));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('withCount / withLastPlayDay are non-mutating', () {
      final before = StreakSnapshot(
        count: 2,
        lastPlayDay: DateTime(2024, 1, 2),
      );
      final c = before.withCount(5);
      final d = before.withLastPlayDay(DateTime(2024, 1, 5));
      expect(c.count, 5);
      expect(c.lastPlayDay, DateTime(2024, 1, 2));
      expect(d.count, 2);
      expect(d.lastPlayDay, DateTime(2024, 1, 5));
      expect(before.count, 2);
    });
  });

  group('StreakMath.recordSession', () {
    const math = StreakMath();

    test('first session ever → count = 1, lastPlayDay = today', () {
      final next = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 1, 9, 30),
      );
      expect(next.count, 1);
      expect(next.lastPlayDay, DateTime(2024, 1, 1));
    });

    test('same calendar day → no-op', () {
      final first = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 1, 9),
      );
      // Same day, later hour — should not change.
      final second = math.recordSession(
        first,
        DateTime(2024, 1, 1, 23, 59),
      );
      expect(second, first);
    });

    test('yesterday → +1', () {
      final first = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 1, 9),
      );
      final second = math.recordSession(
        first,
        DateTime(2024, 1, 2, 10),
      );
      expect(second.count, 2);
      expect(second.lastPlayDay, DateTime(2024, 1, 2));
    });

    test('multi-day consecutive → +1 each', () {
      var s = StreakSnapshot.empty;
      for (var i = 0; i < 5; i++) {
        s = math.recordSession(s, DateTime(2024, 1, 1 + i, 12));
      }
      expect(s.count, 5);
      expect(s.lastPlayDay, DateTime(2024, 1, 5));
    });

    test('gap of 2+ days → reset to 1', () {
      final s1 = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 1),
      );
      final s2 = math.recordSession(
        s1,
        DateTime(2024, 1, 2),
      );
      // Skip the 3rd, play on the 4th.
      final s3 = math.recordSession(
        s2,
        DateTime(2024, 1, 4),
      );
      expect(s3.count, 1);
      expect(s3.lastPlayDay, DateTime(2024, 1, 4));
    });

    test('month boundary — last day of Jan + first of Feb is a streak', () {
      final s1 = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 31),
      );
      final s2 = math.recordSession(
        s1,
        DateTime(2024, 2, 1),
      );
      expect(s2.count, 2);
    });

    test('time-of-day on yesterday still counts as yesterday', () {
      final s1 = math.recordSession(
        StreakSnapshot.empty,
        DateTime(2024, 1, 1, 23, 30),
      );
      // 12:01am the next day is still +1.
      final s2 = math.recordSession(
        s1,
        DateTime(2024, 1, 2, 0, 1),
      );
      expect(s2.count, 2);
    });
  });

  group('InMemoryStreakRepository', () {
    test('starts empty', () {
      final repo = InMemoryStreakRepository();
      expect(repo.load(), StreakSnapshot.empty);
    });

    test('round-trips a snapshot', () async {
      final repo = InMemoryStreakRepository();
      const s = StreakSnapshot(count: 7, lastPlayDay: null);
      await repo.save(s);
      expect(repo.load(), s);
    });
  });

  group('StreakController', () {
    late ProviderContainer container;
    late InMemoryStreakRepository repo;
    late List<int> streamEvents;

    setUp(() {
      repo = InMemoryStreakRepository();
      streamEvents = [];
      container = ProviderContainer(
        overrides: [
          streakRepositoryProvider.overrideWithValue(repo),
        ],
      );
      container
          .read(streakControllerProvider.notifier)
          .streakUpStream
          .listen(streamEvents.add);
    });

    tearDown(() {
      container.dispose();
    });

    test('starts empty', () {
      expect(container.read(streakControllerProvider), StreakSnapshot.empty);
    });

    test('first recordSession sets count to 1, no stream event', () async {
      final c = container.read(streakControllerProvider.notifier);
      final now = DateTime(2024, 1, 1);
      final result = await c.recordSession(now: now);
      expect(result.count, 1);
      expect(container.read(streakControllerProvider).count, 1);
      expect(streamEvents, isEmpty);
    });

    test('second recordSession same day → no-op', () async {
      final c = container.read(streakControllerProvider.notifier);
      await c.recordSession(now: DateTime(2024, 1, 1));
      final before = container.read(streakControllerProvider);
      final result = await c.recordSession(now: DateTime(2024, 1, 1, 18));
      expect(result, before);
      expect(streamEvents, isEmpty);
    });

    test('second recordSession next day → +1, stream event', () async {
      final c = container.read(streakControllerProvider.notifier);
      await c.recordSession(now: DateTime(2024, 1, 1));
      await c.recordSession(now: DateTime(2024, 1, 2));
      expect(container.read(streakControllerProvider).count, 2);
      await Future<void>.delayed(Duration.zero);
      expect(streamEvents, [2]);
    });

    test('gap of 2+ days → reset, no stream event', () async {
      final c = container.read(streakControllerProvider.notifier);
      await c.recordSession(now: DateTime(2024, 1, 1));
      await c.recordSession(now: DateTime(2024, 1, 2)); // 2
      await c.recordSession(now: DateTime(2024, 1, 4)); // gap → 1
      expect(container.read(streakControllerProvider).count, 1);
      await Future<void>.delayed(Duration.zero);
      // Only the first +1 fired an event (2). The reset emits nothing.
      expect(streamEvents, [2]);
    });

    test('persists to repository', () async {
      final c = container.read(streakControllerProvider.notifier);
      await c.recordSession(now: DateTime(2024, 1, 1));
      await c.recordSession(now: DateTime(2024, 1, 2));
      final loaded = repo.load();
      expect(loaded.count, 2);
      expect(loaded.lastPlayDay, DateTime(2024, 1, 2));
    });

    test('reset() drops back to empty', () async {
      final c = container.read(streakControllerProvider.notifier);
      await c.recordSession(now: DateTime(2024, 1, 1));
      await c.reset();
      expect(container.read(streakControllerProvider), StreakSnapshot.empty);
      expect(repo.load(), StreakSnapshot.empty);
    });
  });
}