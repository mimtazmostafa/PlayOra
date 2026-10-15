import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_category.dart';
import '../../data/repositories/recent_searches_repository.dart';
import '../games/games_providers.dart';

/// Riverpod entry point for the recent-searches repository.
/// Override in `main` (with the Hive impl) or in tests (with the in-memory one).
final recentSearchesRepositoryProvider =
    Provider<RecentSearchesRepository>((ref) {
  throw UnimplementedError(
    'recentSearchesRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Reactive view of the recent-search list. Re-emits whenever
/// [recordRecentSearch] / [clearRecentSearches] fires so the Search screen
/// can rebuild without re-reading Hive directly.
class RecentSearchesController extends Notifier<List<String>> {
  @override
  List<String> build() {
    return ref.read(recentSearchesRepositoryProvider).getRecent();
  }

  /// Persist [query] to the front of the recent list. Empty / whitespace
  /// queries are ignored at the repo level.
  Future<void> record(String query) async {
    await ref.read(recentSearchesRepositoryProvider).record(query);
    state = ref.read(recentSearchesRepositoryProvider).getRecent();
  }

  /// Wipe the list (e.g. from a "Clear all" button).
  Future<void> clear() async {
    await ref.read(recentSearchesRepositoryProvider).clear();
    state = const <String>[];
  }
}

final recentSearchesControllerProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
  RecentSearchesController.new,
);

/// Game count per category. Computed once from the full catalog, then
/// cached by Riverpod so every category tile uses the same numbers.
final gameCountByCategoryProvider = Provider<Map<GameCategory, int>>((ref) {
  final asyncGames = ref.watch(gamesProvider);
  final games = asyncGames.valueOrNull ?? const [];
  final out = <GameCategory, int>{};
  for (final category in GameCategory.values) {
    out[category] = 0;
  }
  for (final g in games) {
    out[g.category] = (out[g.category] ?? 0) + 1;
  }
  return out;
});