import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_category.dart';
import '../../data/models/game_model.dart';
import '../../data/repositories/game_repository.dart';
import '../../data/repositories/level_progress_repository.dart';

/// Riverpod entry point for the game repository.
/// Override in `main` (with [LocalJsonGameRepository]) or in tests
/// (with [InMemoryGameRepository]).
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  throw UnimplementedError(
    'gameRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Per-game level progression. Override in `main` with the Hive-backed
/// implementation; tests / previews can swap to the in-memory one.
final levelProgressRepositoryProvider =
    Provider<LevelProgressRepository>((ref) {
  throw UnimplementedError(
    'levelProgressRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Reactive per-game progress. Watches the repository and notifies the
/// UI when a level is unlocked.
final levelProgressProvider =
    FutureProvider.family<LevelProgressSnapshot, String>((ref, gameId) async {
  // Listen to a tick provider so any update triggers a refresh.
  ref.watch(levelProgressTickProvider);
  final repo = ref.read(levelProgressRepositoryProvider);
  return LevelProgressSnapshot(
    gameId: gameId,
    unlocked: repo.unlockedFor(gameId),
    total: repo.totalFor(gameId),
  );
});

/// Bumping this invalidates every [levelProgressProvider] read.
final levelProgressTickProvider = StateProvider<int>((ref) => 0);

/// Helper controller that bumps the tick + writes to the repo.
class LevelProgressController {
  LevelProgressController(this._ref);
  final Ref _ref;

  Future<void> markCompleted(String gameId, int level) async {
    final repo = _ref.read(levelProgressRepositoryProvider);
    await repo.markCompleted(gameId, level);
    _ref.read(levelProgressTickProvider.notifier).state++;
  }

  Future<void> reset(String gameId) async {
    final repo = _ref.read(levelProgressRepositoryProvider);
    await repo.reset(gameId);
    _ref.read(levelProgressTickProvider.notifier).state++;
  }
}

final levelProgressControllerProvider =
    Provider<LevelProgressController>((ref) => LevelProgressController(ref));

/// Immutable snapshot of a game's level-progress state.
class LevelProgressSnapshot {
  const LevelProgressSnapshot({
    required this.gameId,
    required this.unlocked,
    required this.total,
  });
  final String gameId;
  final int unlocked;
  final int total;

  bool isUnlocked(int level) => level >= 1 && level <= unlocked;
}

/// Full game catalog. Exposed as AsyncValue so the UI can render
/// `loading` / `error` / `data` states for free.
final gamesProvider = FutureProvider<List<Game>>((ref) async {
  return ref.read(gameRepositoryProvider).getAllGames();
});

/// Games filtered by [GameCategory]. Pass an enum, get a list.
final gamesByCategoryProvider =
    FutureProvider.family<List<Game>, GameCategory>((ref, category) async {
  return ref.read(gameRepositoryProvider).getByCategory(category);
});

/// Curated hero games for the home banner carousel.
/// The `limit` arg lets callers (and tests) ask for any number of slides.
final featuredGamesProvider =
    FutureProvider.family<List<Game>, int>((ref, limit) async {
  return ref.read(gameRepositoryProvider).getFeatured(limit: limit);
});

/// Single game lookup by id. Returns `null` when the id is unknown.
final gameByIdProvider =
    FutureProvider.family<Game?, String>((ref, id) async {
  return ref.read(gameRepositoryProvider).getById(id);
});

/// Other games in the same category as [gameId], excluding the current game.
/// Empty list if the game is unknown or has no category peers.
final relatedGamesProvider =
    FutureProvider.family<List<Game>, String>((ref, gameId) async {
  final repo = ref.read(gameRepositoryProvider);
  final current = await repo.getById(gameId);
  if (current == null) return const <Game>[];
  final peers = await repo.getByCategory(current.category);
  return peers.where((g) => g.id != gameId).toList(growable: false);
});

/// Search across the catalog. Empty / whitespace queries return the full list.
final gameSearchProvider =
    FutureProvider.family<List<Game>, String>((ref, query) async {
  return ref.read(gameRepositoryProvider).search(query);
});