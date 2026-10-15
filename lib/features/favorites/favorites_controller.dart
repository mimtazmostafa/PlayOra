import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/local/hive_boxes.dart';
import '../../data/registry/game_registry.dart';

/// Favorite gameIds — an ordered [Set] so the Favorites tab can render
/// a stable, user-shaped grid without us imposing a sort order.
///
/// Persistence: stored in the [HiveBoxes.favorites] box under
/// [HiveBoxes.favoritesKey] as `List<String>`. We coerce through a Set
/// at the boundary so the on-disk shape stays deduped even if two
/// writes race.
@immutable
class FavoritesState {
  const FavoritesState(this.ids);
  factory FavoritesState.empty() => const FavoritesState(<String>{});

  /// Unmodifiable view of the favorited game ids in insertion order.
  final Set<String> ids;

  bool contains(String gameId) => ids.contains(gameId);

  FavoritesState copyWith(Set<String>? ids) =>
      FavoritesState(ids ?? this.ids);
}

class FavoritesController extends Notifier<FavoritesState> {
  Box<dynamic>? _box;

  @override
  FavoritesState build() {
    // Favorites don't drive anything else; safe to read once and then
    // mutate in place through [toggle]/[add]/[remove].
    final box = Hive.box<dynamic>(HiveBoxes.favorites);
    _box = box;
    final raw = box.get(HiveBoxes.favoritesKey);
    if (raw is List) {
      return FavoritesState(<String>{
        for (final id in raw)
          if (id is String && GameRegistry.byId(id) != null) id,
      });
    }
    return FavoritesState.empty();
  }

  Box<dynamic> get _b {
    final box = _box;
    if (box == null) {
      throw StateError('FavoritesController.build() was not awaited');
    }
    return box;
  }

  Future<void> _write() async {
    await _b.put(HiveBoxes.favoritesKey, state.ids.toList(growable: false));
  }

  /// Add [gameId] to favorites. No-op when it's already in the set.
  Future<void> add(String gameId) async {
    if (state.ids.contains(gameId)) return;
    state = FavoritesState(<String>{...state.ids, gameId});
    await _write();
  }

  /// Remove [gameId] from favorites. No-op when it's not in the set.
  Future<void> remove(String gameId) async {
    if (!state.ids.contains(gameId)) return;
    final next = <String>{...state.ids}..remove(gameId);
    state = FavoritesState(next);
    await _write();
  }

  /// Toggle membership for [gameId]. Returns the new membership state
  /// (true = favorited).
  Future<bool> toggle(String gameId) async {
    if (state.ids.contains(gameId)) {
      await remove(gameId);
      return false;
    }
    await add(gameId);
    return true;
  }

  /// Wipe every favorite. Wired into the More tab's "Reset progress"
  /// debug action (future).
  Future<void> clear() async {
    state = FavoritesState.empty();
    await _write();
  }
}

final favoritesControllerProvider =
    NotifierProvider<FavoritesController, FavoritesState>(
  FavoritesController.new,
);

/// Convenience selector — `true` when [gameId] is favorited.
final isFavoriteProvider = Provider.family<bool, String>((ref, gameId) {
  return ref.watch(
    favoritesControllerProvider.select((s) => s.contains(gameId)),
  );
});

/// Favorited [RegistryGame]s in insertion order. Strips ids that no
/// longer exist in the registry so deleted games don't leave ghost
/// entries on the Favorites screen.
final favoritedGamesProvider = Provider<List<RegistryGame>>((ref) {
  final ids = ref.watch(favoritesControllerProvider).ids;
  final out = <RegistryGame>[];
  for (final id in ids) {
    final g = GameRegistry.byId(id);
    if (g != null) out.add(g);
  }
  return out;
});
