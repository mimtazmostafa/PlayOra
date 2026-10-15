import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'data/api/bdapps_api.dart';
import 'data/local/game_database.dart';
import 'data/local/hive_setup.dart';
import 'data/local/user_stats_dao.dart';
import 'data/repositories/achievements_repository.dart';
import 'data/repositories/favorites_repository.dart';
import 'data/repositories/game_repository.dart';
import 'data/repositories/onboarding_repository.dart';

import 'data/repositories/play_history_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/recent_searches_repository.dart';
import 'data/repositories/level_progress_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/rewards_repository.dart';
import 'data/repositories/streak_repository.dart';
import 'data/repositories/daily_challenge_repository.dart';
import 'data/repositories/subscription_repository.dart';
import 'features/achievements/achievements_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/categories/categories_providers.dart';
import 'features/daily_challenge/daily_challenge_controller.dart';
import 'features/games/games_providers.dart';
import 'features/onboarding/onboarding_controller.dart';
import 'features/profile/played_games_controller.dart';
import 'features/profile/profile_controller.dart';
import 'features/rewards/rewards_controller.dart';
import 'features/settings/theme_mode_controller.dart';
import 'features/streak/streak_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-fetch Google Fonts so the first frame renders the right faces.
  // Failure is non-fatal — google_fonts falls back to the platform default.
  await GoogleFonts.pendingFonts();

  await HiveSetup.init();
  final settingsRepo = await HiveSettingsRepository.open();
  // Onboarding flag lives in the same `app_settings` box, so reuse the handle
  // instead of opening a second box with the same name.
  final onboardingRepo = HiveOnboardingRepository(settingsRepo.box);
  final gameRepo = await LocalJsonGameRepository.load();
  final recentSearchesRepo = await HiveRecentSearchesRepository.open();
  final favoritesRepo = await HiveFavoritesRepository.open();
  final rewardsRepo = await HiveRewardsRepository.open();
  final streakRepo = await HiveStreakRepository.open();
  final dailyChallengeRepo = await HiveDailyChallengeRepository.open();
  final achievementsRepo = await HiveAchievementsRepository.open();
  final profileRepo = await HiveProfileRepository.open();
  final playHistoryRepo = await HivePlayHistoryRepository.open();
  final levelProgressRepo = await HiveLevelProgressRepository.open();
  // Subscription session (Hive-backed) and the upstream bdapps REST
  // client. Both are wired through Riverpod overrides so tests /
  // previews can swap them without touching the real network or
  // persistent storage.
  final subscriptionRepo = await HiveSubscriptionRepository.open();
  final bdAppsApi = BdAppsApi();

  // Single source of truth for the offline database — wires every Hive
  // box through DAO-style repositories. The facades still expose the
  // same repositories the previous bootstrap did so the existing
  // controllers don't need to change.
  final gameDb = await GameDatabase.init();

  runApp(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepo),
        gameRepositoryProvider.overrideWithValue(gameRepo),
        recentSearchesRepositoryProvider.overrideWithValue(recentSearchesRepo),
        favoritesRepositoryProvider.overrideWithValue(favoritesRepo),
        rewardsRepositoryProvider.overrideWithValue(rewardsRepo),
        streakRepositoryProvider.overrideWithValue(streakRepo),
        dailyChallengeRepositoryProvider
            .overrideWithValue(dailyChallengeRepo),
        achievementsRepositoryProvider.overrideWithValue(achievementsRepo),
        profileRepositoryProvider.overrideWithValue(profileRepo),
        playHistoryRepositoryProvider.overrideWithValue(playHistoryRepo),
        levelProgressRepositoryProvider
            .overrideWithValue(levelProgressRepo),
        // Auth gate — bdapps REST client and the Hive-backed session
        // repository. Both are required for the Subscribe / Login /
        // Logout / Unsubscribe flows.
        bdAppsApiProvider.overrideWithValue(bdAppsApi),
        subscriptionRepositoryProvider.overrideWithValue(subscriptionRepo),
        // The More tab reads aggregate stats from this DAO. The same
        // GameDatabase facade owns it, so call sites that want to
        // record a finished session can either reach for the DAO
        // directly or use `gameDb.userStatsDao`.
        userStatsDaoProvider.overrideWithValue(gameDb.userStatsDao),
      ],
      child: const PlayNestApp(),
    ),
  );
}
