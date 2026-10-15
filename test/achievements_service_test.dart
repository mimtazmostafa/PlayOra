import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/models/game_category.dart';
import 'package:playnest/data/repositories/achievements_repository.dart';
import 'package:playnest/features/achievements/achievement_model.dart';
import 'package:playnest/features/achievements/achievements_controller.dart';
import 'package:playnest/features/rewards/rewards_model.dart';
import 'package:playnest/features/streak/streak_model.dart';

void main() {
  group('AchievementCatalog', () {
    test('has 8 entries with unique ids', () {
      final ids = AchievementCatalog.all.map((a) => a.id).toSet();
      expect(AchievementCatalog.all.length, ids.length);
      // Every expected id is present.
      for (final id in const [
        'first_game',
        'streak_3',
        'streak_7',
        'all_categories',
        'level_5',
        'level_10',
        'games_20',
        'games_50',
      ]) {
        expect(ids, contains(id));
      }
    });

    test('byId returns the right definition or null', () {
      expect(AchievementCatalog.byId('streak_3')?.title, '3-Day Streak');
      expect(AchievementCatalog.byId('does_not_exist'), isNull);
    });

    test('every definition has a non-empty title, description, and icon', () {
      for (final a in AchievementCatalog.all) {
        expect(a.title, isNotEmpty);
        expect(a.description, isNotEmpty);
        expect(a.icon, isNotNull);
      }
    });
  });

  group('AchievementCondition — pure predicates', () {
    AchievementContext ctx({
      int xp = 0,
      int streakCount = 0,
      Set<GameCategory> categories = const <GameCategory>{},
      int totalGames = 0,
    }) {
      return AchievementContext(
        rewards: RewardsSnapshot(coins: 0, xp: xp),
        streak: StreakSnapshot(
          count: streakCount,
          lastPlayDay: streakCount == 0 ? null : DateTime(2024, 1, 1),
        ),
        playedCategories: categories,
        totalGamesPlayed: totalGames,
      );
    }

    AchievementCondition cond(String id) =>
        AchievementCatalog.byId(id)!.condition;

    test('first_game unlocks at totalGamesPlayed >= 1', () {
      expect(cond('first_game')(ctx(totalGames: 0)), isFalse);
      expect(cond('first_game')(ctx(totalGames: 1)), isTrue);
    });

    test('streak_3 unlocks at streak.count == 3', () {
      expect(cond('streak_3')(ctx(streakCount: 2)), isFalse);
      expect(cond('streak_3')(ctx(streakCount: 3)), isTrue);
    });

    test('streak_7 unlocks at streak.count == 7', () {
      expect(cond('streak_7')(ctx(streakCount: 6)), isFalse);
      expect(cond('streak_7')(ctx(streakCount: 7)), isTrue);
    });

    test('all_categories unlocks when every category has been played', () {
      final oneShort = <GameCategory>{
        for (final c in GameCategory.values)
          if (c != GameCategory.values.last) c,
      };
      expect(cond('all_categories')(ctx(categories: oneShort)), isFalse);
      expect(
        cond('all_categories')(ctx(categories: GameCategory.values.toSet())),
        isTrue,
      );
    });

    test('level_5 unlocks at xp == 800 (xpPerLevelBase=50, (5-1)^2*50)', () {
      // xp 799 → level 4, xp 800 → level 5
      expect(cond('level_5')(ctx(xp: 799)), isFalse);
      expect(cond('level_5')(ctx(xp: 800)), isTrue);
    });

    test('level_10 unlocks at xp == 4050', () {
      // (10-1)^2 * 50 = 81 * 50 = 4050
      expect(cond('level_10')(ctx(xp: 4049)), isFalse);
      expect(cond('level_10')(ctx(xp: 4050)), isTrue);
    });

    test('games_20 unlocks at totalGamesPlayed == 20', () {
      expect(cond('games_20')(ctx(totalGames: 19)), isFalse);
      expect(cond('games_20')(ctx(totalGames: 20)), isTrue);
    });

    test('games_50 unlocks at totalGamesPlayed == 50', () {
      expect(cond('games_50')(ctx(totalGames: 49)), isFalse);
      expect(cond('games_50')(ctx(totalGames: 50)), isTrue);
    });
  });

  group('InMemoryAchievementsRepository', () {
    test('starts empty', () {
      final repo = InMemoryAchievementsRepository();
      expect(repo.load(), isEmpty);
    });

    test('round-trips an unlock set', () async {
      final repo = InMemoryAchievementsRepository();
      final stamp = DateTime(2024, 5, 1);
      await repo.save({'first_game': stamp, 'streak_3': stamp});
      final loaded = repo.load();
      expect(loaded['first_game'], stamp);
      expect(loaded['streak_3'], stamp);
    });

    test('seed pre-populates load()', () {
      final repo = InMemoryAchievementsRepository();
      final stamp = DateTime(2024, 6, 1);
      repo.seed({'level_5': stamp});
      expect(repo.load(), {'level_5': stamp});
    });

    test('load() returns an unmodifiable view', () {
      final repo = InMemoryAchievementsRepository();
      final view = repo.load();
      expect(() => view['x'] = DateTime.now(), throwsUnsupportedError);
    });
  });

  group('AchievementsController', () {
    late ProviderContainer container;
    late InMemoryAchievementsRepository repo;
    late List<List<AchievementUnlock>> streamBatches;

    AchievementContext ctx({
      int xp = 0,
      int streakCount = 0,
      Set<GameCategory> categories = const <GameCategory>{},
      int totalGames = 0,
    }) {
      return AchievementContext(
        rewards: RewardsSnapshot(coins: 0, xp: xp),
        streak: StreakSnapshot(
          count: streakCount,
          lastPlayDay: streakCount == 0 ? null : DateTime(2024, 1, 1),
        ),
        playedCategories: categories,
        totalGamesPlayed: totalGames,
      );
    }

    setUp(() {
      repo = InMemoryAchievementsRepository();
      streamBatches = [];
      container = ProviderContainer(
        overrides: [
          achievementsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      container
          .read(achievementsControllerProvider.notifier)
          .unlockedStream
          .listen(streamBatches.add);
    });

    tearDown(() {
      container.dispose();
    });

    test('starts empty', () {
      expect(container.read(achievementsControllerProvider), isEmpty);
    });

    test('recordSession unlocks first_game on first play', () async {
      final c = container.read(achievementsControllerProvider.notifier);
      final result = await c.recordSession(ctx: ctx(totalGames: 1));
      expect(result, hasLength(1));
      expect(result.single.definition.id, 'first_game');
      expect(container.read(achievementsControllerProvider)['first_game'],
          isNotNull);
    });

    test('recordSession persists unlocks to the repository', () async {
      final c = container.read(achievementsControllerProvider.notifier);
      final stamp = DateTime(2024, 5, 1, 12);
      await c.recordSession(
        ctx: ctx(totalGames: 1, streakCount: 3),
        now: stamp,
      );
      final loaded = repo.load();
      expect(loaded['first_game'], stamp);
      expect(loaded['streak_3'], stamp);
    });

    test('recordSession unlocks multiple at once when several thresholds met',
        () async {
      final c = container.read(achievementsControllerProvider.notifier);
      final result = await c.recordSession(
        ctx: ctx(totalGames: 20, streakCount: 7, xp: 4050),
      );
      final ids = result.map((u) => u.definition.id).toSet();
      expect(
        ids,
        containsAll(<String>{
          'first_game',
          'streak_3',
          'streak_7',
          'level_5',
          'level_10',
          'games_20',
        }),
      );
    });

    test('recordSession is idempotent — no duplicates on second call',
        () async {
      final c = container.read(achievementsControllerProvider.notifier);
      await c.recordSession(ctx: ctx(totalGames: 1));
      final second = await c.recordSession(ctx: ctx(totalGames: 1));
      expect(second, isEmpty);
      // State still has only one entry for first_game.
      expect(
        container.read(achievementsControllerProvider).keys,
        equals(<String>{'first_game'}),
      );
    });

    test('recordSession does not mutate state when nothing new unlocks',
        () async {
      final c = container.read(achievementsControllerProvider.notifier);
      // Zero progress → nothing matches.
      final before = container.read(achievementsControllerProvider);
      final result = await c.recordSession(ctx: ctx());
      expect(result, isEmpty);
      final after = container.read(achievementsControllerProvider);
      // Same identity — no rebuild triggered.
      expect(identical(before, after), isTrue);
    });

    test('emits a stream event for every recordSession that unlocks something',
        () async {
      final c = container.read(achievementsControllerProvider.notifier);
      await c.recordSession(ctx: ctx(totalGames: 1));
      await Future<void>.delayed(Duration.zero);
      expect(streamBatches, hasLength(1));
      expect(streamBatches.first.single.definition.id, 'first_game');
    });

    test('does not emit when nothing new unlocks', () async {
      final c = container.read(achievementsControllerProvider.notifier);
      await c.recordSession(ctx: ctx());
      await Future<void>.delayed(Duration.zero);
      expect(streamBatches, isEmpty);
    });

    test('pre-seeded unlocks survive controller build', () {
      final stamp = DateTime(2024, 1, 1);
      repo.seed({'first_game': stamp});
      final fresh = ProviderContainer(
        overrides: [achievementsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(fresh.dispose);
      final state = fresh.read(achievementsControllerProvider);
      expect(state['first_game'], stamp);
    });

    test('reset() drops every unlock back to empty and persists', () async {
      final c = container.read(achievementsControllerProvider.notifier);
      await c.recordSession(ctx: ctx(totalGames: 1));
      expect(container.read(achievementsControllerProvider), isNotEmpty);
      await c.reset();
      expect(container.read(achievementsControllerProvider), isEmpty);
      expect(repo.load(), isEmpty);
    });
  });
}