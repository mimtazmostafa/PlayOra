import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/play_history_repository.dart';

/// Provider for the underlying [PlayHistoryRepository]. Overridden in
/// `main.dart` with the Hive-backed implementation; tests override
/// with [InMemoryPlayHistoryRepository].
final playHistoryRepositoryProvider = Provider<PlayHistoryRepository>((ref) {
  throw UnimplementedError(
    'playHistoryRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Reactive view of the per-game last-played map.
///
/// Sorted by `lastPlayed` descending so the Play History screen can
/// render the list in "most recent first" order without resorting.
class PlayedGamesController
    extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    return ref.read(playHistoryRepositoryProvider).load();
  }

  /// Record [gameId] as just played. Persists to the repo and emits
  /// the new map so any subscribed screen rebuilds.
  Future<void> recordPlay(String gameId, {DateTime? at}) async {
    final stamp = at ?? DateTime.now();
    final repo = ref.read(playHistoryRepositoryProvider);
    await repo.recordPlay(gameId, at: stamp);
    state = repo.load();
  }

  /// True if the player has ever played [gameId].
  bool hasPlayed(String gameId) => state.containsKey(gameId);

  /// Timestamp of the last play, or null when [gameId] has never
  /// been played.
  DateTime? lastPlayedAt(String gameId) => state[gameId];

  /// Most-recent entries first — handy for the Play History list.
  List<MapEntry<String, DateTime>> sortedRecent() {
    final entries = state.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Lifetime count of distinct games played (not session count —
  /// each gameId is counted at most once).
  int get distinctGamesPlayed => state.length;
}

final playedGamesControllerProvider =
    NotifierProvider<PlayedGamesController, Map<String, DateTime>>(
  PlayedGamesController.new,
);
