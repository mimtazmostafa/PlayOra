import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/repositories/daily_challenge_repository.dart';
import 'package:playnest/features/daily_challenge/daily_challenge_model.dart';

void main() {
  group('DailyChallengeMath', () {
    const math = DailyChallengeMath();

    test('dayKey is zero-padded YYYY-MM-DD', () {
      expect(math.dayKey(DateTime(2024, 1, 5)), '2024-01-05');
      expect(math.dayKey(DateTime(2024, 12, 31)), '2024-12-31');
    });

    test('dayHash is in [0, 1)', () {
      for (final d in [
        DateTime(2024, 1, 1),
        DateTime(2024, 6, 15),
        DateTime(2024, 12, 31),
        DateTime(2025, 2, 29),
      ]) {
        final h = math.dayHash(d);
        expect(h, greaterThanOrEqualTo(0.0));
        expect(h, lessThan(1.0));
      }
    });

    test('same day → same hash', () {
      final a = math.dayHash(DateTime(2024, 3, 10, 1, 2));
      final b = math.dayHash(DateTime(2024, 3, 10, 23, 59));
      expect(a, b);
    });

    test('different days → likely different hashes', () {
      final a = math.dayHash(DateTime(2024, 3, 10));
      final b = math.dayHash(DateTime(2024, 3, 11));
      expect(a, isNot(b));
    });

    test('pickGameId is deterministic for the same day', () {
      const catalog = ['a', 'b', 'c', 'd', 'e'];
      final day = DateTime(2024, 5, 1);
      expect(math.pickGameId(day, catalog), math.pickGameId(day, catalog));
    });

    test('pickGameId returns null for empty catalog', () {
      expect(math.pickGameId(DateTime(2024, 5, 1), const []), isNull);
    });

    test('pickGameId generally varies across consecutive days', () {
      const catalog = [
        'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
      ];
      final picks = <String>{};
      for (var i = 0; i < 30; i++) {
        final p = math.pickGameId(DateTime(2024, 1, 1 + i), catalog);
        if (p != null) picks.add(p);
      }
      // Across 30 days with 10 games, we should see more than one
      // unique pick (very rarely we'd miss this by bad luck, but the
      // hash multiplication makes it overwhelmingly likely).
      expect(picks.length, greaterThan(1));
    });

    test('targetFor is deterministic for the same (gameId, day)', () {
      final t1 = math.targetFor('sudoku-master', DateTime(2024, 5, 1));
      final t2 = math.targetFor('sudoku-master', DateTime(2024, 5, 1));
      expect(t1, t2);
    });

    test('targetFor is one of three buckets per game', () {
      // Across 30 days the same game picks 3 distinct targets.
      final picked = <int>{};
      for (var i = 0; i < 30; i++) {
        picked.add(math.targetFor('sudoku-master', DateTime(2024, 1, 1 + i)));
      }
      expect(picked.length, lessThanOrEqualTo(3));
      expect(picked.length, greaterThanOrEqualTo(1));
    });

    test('targetFor is positive', () {
      for (final id in ['a', 'b', 'sudoku-master', 'block-blast']) {
        for (var i = 0; i < 7; i++) {
          expect(math.targetFor(id, DateTime(2024, 1, 1 + i)), greaterThan(0));
        }
      }
    });
  });

  group('DailyChallenge', () {
    test('value equality', () {
      const a = DailyChallenge(
        dayKey: '2024-01-01',
        gameId: 'x',
        targetScore: 50,
        bestScore: 10,
        isCompleted: false,
      );
      const b = DailyChallenge(
        dayKey: '2024-01-01',
        gameId: 'x',
        targetScore: 50,
        bestScore: 10,
        isCompleted: false,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('withBestScore is non-mutating', () {
      const a = DailyChallenge(
        dayKey: '2024-01-01',
        gameId: 'x',
        targetScore: 50,
        bestScore: 10,
        isCompleted: false,
      );
      final b = a.withBestScore(40);
      expect(b.bestScore, 40);
      expect(a.bestScore, 10);
    });

    test('withCompleted is non-mutating and bumps bestScore', () {
      const a = DailyChallenge(
        dayKey: '2024-01-01',
        gameId: 'x',
        targetScore: 50,
        bestScore: 10,
        isCompleted: false,
      );
      final b = a.withCompleted(value: true, bestScore: 60);
      expect(b.isCompleted, isTrue);
      expect(b.bestScore, 60);
      expect(a.isCompleted, isFalse);
    });
  });

  group('InMemoryDailyChallengeRepository', () {
    test('load returns null when no record', () {
      final repo = InMemoryDailyChallengeRepository();
      expect(repo.load('2024-01-01'), isNull);
    });

    test('round-trips a record', () async {
      final repo = InMemoryDailyChallengeRepository();
      const r = DailyChallengeRecord(
        dayKey: '2024-01-01',
        bestScore: 100,
        isCompleted: true,
      );
      await repo.save(r);
      expect(repo.load('2024-01-01'), r);
    });

    test('keeps records per day', () async {
      final repo = InMemoryDailyChallengeRepository();
      await repo.save(const DailyChallengeRecord(
        dayKey: '2024-01-01',
        bestScore: 50,
        isCompleted: false,
      ));
      await repo.save(const DailyChallengeRecord(
        dayKey: '2024-01-02',
        bestScore: 70,
        isCompleted: true,
      ));
      expect(repo.load('2024-01-01')!.bestScore, 50);
      expect(repo.load('2024-01-02')!.bestScore, 70);
    });
  });

  group('DailyChallengeRecord.fromMap', () {
    test('handles missing fields gracefully', () {
      final r = DailyChallengeRecord.fromMap('2024-01-01', <dynamic, dynamic>{});
      expect(r.dayKey, '2024-01-01');
      expect(r.bestScore, 0);
      expect(r.isCompleted, isFalse);
    });

    test('reads int + bool fields', () {
      final r = DailyChallengeRecord.fromMap('2024-01-01', <dynamic, dynamic>{
        'bestScore': 42,
        'isCompleted': true,
      });
      expect(r.bestScore, 42);
      expect(r.isCompleted, isTrue);
    });
  });
}
