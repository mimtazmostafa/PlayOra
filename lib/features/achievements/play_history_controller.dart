import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_category.dart';
import '../games/games_providers.dart';
import '../rewards/rewards_controller.dart';
import '../streak/streak_controller.dart';
import 'achievement_model.dart';

/// Lifetime play history that the achievements controller consumes.
///
/// In-memory only — the achievements controller *persists* the unlock
/// records, but this provider just keeps the rolling state for the
/// current session so the unlock conditions have something to read
/// against. Every app launch starts at zero; the achievements screen
/// will report "Locked" for any condition requiring total-plays, but
/// the unlock records persisted across launches are unaffected.
///
/// The hook site is the post-game rewards screen, which calls
/// [recordPlay] with the game whose session just ended.
class PlayHistoryState {
  const PlayHistoryState({
    required this.playedCategories,
    required this.totalGamesPlayed,
  });

  final Set<GameCategory> playedCategories;
  final int totalGamesPlayed;

  static const PlayHistoryState empty = PlayHistoryState(
    playedCategories: <GameCategory>{},
    totalGamesPlayed: 0,
  );
}

class PlayHistoryController extends Notifier<PlayHistoryState> {
  @override
  PlayHistoryState build() => PlayHistoryState.empty;

  /// Increment the play count and add [category] to the played set.
  /// Returns the new state.
  PlayHistoryState recordPlay(GameCategory category) {
    final next = PlayHistoryState(
      playedCategories: <GameCategory>{...state.playedCategories, category},
      totalGamesPlayed: state.totalGamesPlayed + 1,
    );
    state = next;
    return next;
  }
}

final playHistoryControllerProvider =
    NotifierProvider<PlayHistoryController, PlayHistoryState>(
  PlayHistoryController.new,
);

/// Convenience: build the [AchievementContext] the post-game hook
/// needs in one place. Reads every provider once so the call site
/// stays clean.
AchievementContext buildAchievementContext(WidgetRef ref) {
  final rewards = ref.read(rewardsControllerProvider);
  final streak = ref.read(streakControllerProvider);
  final history = ref.read(playHistoryControllerProvider);
  return AchievementContext(
    rewards: rewards,
    streak: streak,
    playedCategories: history.playedCategories,
    totalGamesPlayed: history.totalGamesPlayed,
  );
}

/// Looks up a game's category from the catalog. Falls back to
/// `arcade` if the catalog isn't loaded yet — the conditions only
/// check whether a category was ever played, so the worst-case miss
/// just delays the "all categories" unlock by one record.
GameCategory resolveGameCategory(
  WidgetRef ref,
  String gameId,
) {
  final games = ref.read(gamesProvider).valueOrNull;
  if (games == null) return GameCategory.arcade;
  for (final g in games) {
    if (g.id == gameId) return g.category;
  }
  return GameCategory.arcade;
}
