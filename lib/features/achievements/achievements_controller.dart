import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/achievements_repository.dart';
import 'achievement_model.dart';

/// Reactive achievements state + persistence boundary.
///
/// Owns the map `{ id -> unlockedAt }` for the player's unlocked
/// achievements and writes any change to the repository. The unlock
/// evaluation is pure: callers pass in a fresh [AchievementContext],
/// we walk [AchievementCatalog.all] and persist any new unlocks.
///
/// When one or more new unlocks happen, every newly-unlocked
/// [AchievementDefinition] is emitted on [unlockedStream] so the
/// global overlay can celebrate.
class AchievementsController extends Notifier<Map<String, DateTime>> {
  late AchievementsRepository _repo;
  final StreamController<List<AchievementUnlock>> _unlockedController =
      StreamController<List<AchievementUnlock>>.broadcast();

  /// Emitted once per [recordSession] call with every *new* unlock
  /// (empty list when nothing changed). The overlay listens to this
  /// and shows one burst per unlock.
  Stream<List<AchievementUnlock>> get unlockedStream =>
      _unlockedController.stream;

  @override
  Map<String, DateTime> build() {
    _repo = ref.read(achievementsRepositoryProvider);
    ref.onDispose(() {
      if (!_unlockedController.isClosed) {
        _unlockedController.close();
      }
    });
    return _repo.load();
  }

  /// Evaluate every achievement's condition against [ctx] and persist
  /// any newly-unlocked ones. Returns the list of new unlocks (may be
  /// empty). The return value is also published on [unlockedStream].
  ///
  /// The controller does not mutate the state when nothing new
  /// unlocks — that keeps the build pipeline stable and avoids
  /// spurious rebuilds.
  Future<List<AchievementUnlock>> recordSession({
    required AchievementContext ctx,
    DateTime? now,
  }) async {
    final current = state;
    final at = now ?? DateTime.now();
    final newlyUnlocked = <AchievementUnlock>[];

    var next = current;
    for (final def in AchievementCatalog.all) {
      if (next.containsKey(def.id)) continue;
      if (def.condition(ctx)) {
        next = <String, DateTime>{...next, def.id: at};
        newlyUnlocked.add(AchievementUnlock(definition: def, unlockedAt: at));
      }
    }

    if (newlyUnlocked.isEmpty) {
      return const <AchievementUnlock>[];
    }

    state = next;
    await _repo.save(next);

    if (!_unlockedController.isClosed) {
      _unlockedController.add(newlyUnlocked);
    }
    return newlyUnlocked;
  }

  /// Test helper: drop every unlock back to empty.
  Future<void> reset() async {
    state = const <String, DateTime>{};
    await _repo.save(const <String, DateTime>{});
  }
}

/// Provider for the underlying [AchievementsRepository]. Overridden
/// in `main.dart` with the Hive-backed implementation; tests override
/// with [InMemoryAchievementsRepository].
final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  throw UnimplementedError(
    'achievementsRepositoryProvider must be overridden in ProviderScope',
  );
});

final achievementsControllerProvider =
    NotifierProvider<AchievementsController, Map<String, DateTime>>(
  AchievementsController.new,
);

/// Convenience stream provider that surfaces the latest unlock batch
/// to overlays / global listeners.
final achievementUnlockedStreamProvider =
    StreamProvider<List<AchievementUnlock>>((ref) {
  final controller = ref.watch(achievementsControllerProvider.notifier);
  return controller.unlockedStream;
});
