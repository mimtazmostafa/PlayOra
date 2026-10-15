import 'package:hive_flutter/hive_flutter.dart';

import '../repositories/play_history_repository.dart';
import '../repositories/rewards_repository.dart';
import '../repositories/streak_repository.dart';
import '../repositories/achievements_repository.dart';
import '../repositories/daily_challenge_repository.dart';
import 'hive_boxes.dart';
import 'user_stats_dao.dart';

/// Centralized "GameDatabase" facade.
///
/// The app's offline persistence is built on top of Hive (see
/// `hive_boxes.dart`). This class surfaces the existing Hive-backed
/// repositories through a single, easy-to-inject entry point — the
/// shape a Room database would have if we migrated to SQLite later.
///
/// All callers should read [GameDatabase.instance] (set up at startup
/// via [GameDatabase.init]) and then call DAOs:
///   * [userStatsDao] — high scores, play counts, total XP.
///   * [streakDao] — daily streak snapshot.
///   * [rewardsDao] — coins, XP.
///   * [achievementsDao] — unlocked achievements.
///   * [dailyChallengeDao] — daily challenge records.
///   * [playHistoryDao] — last-played map.
class GameDatabase {
  GameDatabase._({
    required this.userStatsDao,
    required this.streakDao,
    required this.rewardsDao,
    required this.achievementsDao,
    required this.dailyChallengeDao,
    required this.playHistoryDao,
  });

  /// Initialise and open every Hive box used by the game database.
  /// Call once from `main()` after `HiveSetup.init`.
  static Future<GameDatabase> init() async {
    final results = await Future.wait([
      Hive.openBox<dynamic>(HiveBoxes.appSettings),
      Hive.openBox<dynamic>(HiveBoxes.userProfile),
      Hive.openBox<dynamic>(HiveBoxes.gameLibrary),
      Hive.openBox<dynamic>(HiveBoxes.rewards),
      Hive.openBox<dynamic>(HiveBoxes.streak),
      Hive.openBox<dynamic>(HiveBoxes.dailyChallenge),
      Hive.openBox<dynamic>(HiveBoxes.achievements),
      Hive.openBox<dynamic>(HiveBoxes.playHistory),
    ]);
    final appSettings = results[0];
    final userProfile = results[1];
    final gameLibrary = results[2];
    final rewards = results[3];
    final streak = results[4];
    final dailyChallenge = results[5];
    final achievements = results[6];
    final playHistory = results[7];

    final instance = GameDatabase._(
      userStatsDao: HiveUserStatsDao(
        playHistory: playHistory,
        userProfile: userProfile,
        gameLibrary: gameLibrary,
        appSettings: appSettings,
      ),
      streakDao: HiveStreakRepository(streak),
      rewardsDao: HiveRewardsRepository(rewards),
      achievementsDao: HiveAchievementsRepository(achievements),
      dailyChallengeDao: HiveDailyChallengeRepository(dailyChallenge),
      playHistoryDao: HivePlayHistoryRepository(playHistory),
    );
    _instance = instance;
    return instance;
  }

  static GameDatabase? _instance;

  /// Late-bound singleton; throws if [GameDatabase.init] hasn't run.
  static GameDatabase get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'GameDatabase.init() must be awaited before accessing instance.',
      );
    }
    return i;
  }

  final UserStatsDao userStatsDao;
  final StreakRepository streakDao;
  final RewardsRepository rewardsDao;
  final AchievementsRepository achievementsDao;
  final DailyChallengeRepository dailyChallengeDao;
  final PlayHistoryRepository playHistoryDao;
}
