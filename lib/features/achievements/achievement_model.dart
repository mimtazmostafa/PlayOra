import 'package:flutter/material.dart';

import '../../data/models/game_category.dart';
import '../rewards/rewards_model.dart';
import '../streak/streak_model.dart';

/// Snapshot of the player's state at the moment a game ends.
///
/// The achievements controller consumes one of these on every
/// [AchievementsController.recordSession] call and evaluates each
/// definition's condition against it. Passing everything in a single
/// value (instead of having the controller reach into six other
/// providers) keeps the unlock logic pure and trivially testable.
class AchievementContext {
  const AchievementContext({
    required this.rewards,
    required this.streak,
    required this.playedCategories,
    required this.totalGamesPlayed,
  });

  /// Current rewards snapshot (coins + xp, drives level math).
  final RewardsSnapshot rewards;

  /// Current streak snapshot (count + last-play-day).
  final StreakSnapshot streak;

  /// The set of distinct categories the player has played at least
  /// one game in. Persisted across sessions.
  final Set<GameCategory> playedCategories;

  /// Lifetime count of game sessions, including the one that just
  /// ended. Persisted across sessions.
  final int totalGamesPlayed;
}

/// A predicate that decides whether a single achievement is unlocked
/// given the current [AchievementContext]. Implementations should be
/// pure — no I/O, no time reads so they remain testable.
typedef AchievementCondition = bool Function(AchievementContext ctx);

/// Static description of an achievement.
///
/// The catalog is a fixed list built up in [AchievementCatalog]. The
/// id is the persistence key — never change it once shipped, because
/// unlocked records are keyed by id.
@immutable
class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.condition,
  });

  /// Stable unique id. Persistence key for the unlock record.
  final String id;

  /// Short title shown on the badge tile.
  final String title;

  /// One-line description. Doubles as the "what to do" hint for the
  /// locked state.
  final String description;

  /// Material icon used on the badge.
  final IconData icon;

  /// Pure predicate evaluated against the current context.
  final AchievementCondition condition;

  @override
  bool operator ==(Object other) => other is AchievementDefinition && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Payload emitted the first time an achievement unlocks. Used by
/// the global overlay to celebrate; also returned from the
/// controller's record session for callers that want to react
/// inline.
class AchievementUnlock {
  const AchievementUnlock({
    required this.definition,
    required this.unlockedAt,
  });

  final AchievementDefinition definition;
  final DateTime unlockedAt;
}

/// Fixed list of achievements the player can earn.
///
/// Add new entries here (and never change an existing id). The
/// order in the list is the render order on the Achievements grid.
class AchievementCatalog {
  AchievementCatalog._();

  static final List<AchievementDefinition> all = <AchievementDefinition>[
    AchievementDefinition(
      id: 'first_game',
      title: 'First Steps',
      description: 'Play your first game.',
      icon: Icons.play_arrow_rounded,
      condition: (ctx) => ctx.totalGamesPlayed >= 1,
    ),
    AchievementDefinition(
      id: 'streak_3',
      title: '3-Day Streak',
      description: 'Play on three consecutive days.',
      icon: Icons.local_fire_department_rounded,
      condition: (ctx) => ctx.streak.count >= 3,
    ),
    AchievementDefinition(
      id: 'streak_7',
      title: '7-Day Streak',
      description: 'Play on seven consecutive days.',
      icon: Icons.whatshot_rounded,
      condition: (ctx) => ctx.streak.count >= 7,
    ),
    AchievementDefinition(
      id: 'all_categories',
      title: 'Well-Rounded',
      description: 'Try every game category at least once.',
      icon: Icons.category_rounded,
      condition: (ctx) =>
          ctx.playedCategories.length >= GameCategory.values.length,
    ),
    AchievementDefinition(
      id: 'level_5',
      title: 'Rising Star',
      description: 'Reach Level 5.',
      icon: Icons.star_rounded,
      condition: (ctx) =>
          const RewardsCurve().levelFor(ctx.rewards.xp) >= 5,
    ),
    AchievementDefinition(
      id: 'level_10',
      title: 'Veteran',
      description: 'Reach Level 10.',
      icon: Icons.workspace_premium_rounded,
      condition: (ctx) =>
          const RewardsCurve().levelFor(ctx.rewards.xp) >= 10,
    ),
    AchievementDefinition(
      id: 'games_20',
      title: 'Devoted',
      description: 'Play 20 games in total.',
      icon: Icons.casino_rounded,
      condition: (ctx) => ctx.totalGamesPlayed >= 20,
    ),
    AchievementDefinition(
      id: 'games_50',
      title: 'Addicted',
      description: 'Play 50 games in total.',
      icon: Icons.emoji_events_rounded,
      condition: (ctx) => ctx.totalGamesPlayed >= 50,
    ),
  ];

  /// Lookup by id. Returns null when the id is not in the catalog.
  static AchievementDefinition? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}
