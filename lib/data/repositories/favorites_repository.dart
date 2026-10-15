import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Persists the user's set of favorited game ids.
///
/// Two implementations:
/// - [HiveFavoritesRepository] — backed by Hive (production).
/// - [InMemoryFavoritesRepository] — for tests / previews.
///
/// Stored as an ordered `List<String>` of game ids under [HiveBoxes.favoritesKey]
/// so the "favorite order" could be surfaced later if desired. The set
/// semantics today just dedupe on insert and treat order as "most-recent first".
abstract class FavoritesRepository {
  /// Snapshot of currently favorited game ids, most-recently favorited first.
  List<String> getFavorites();

  /// Whether [gameId] is currently a favorite.
  bool isFavorite(String gameId);

  /// Add [gameId] to the favorites set (no-op if already present, but it does
  /// float to the front so the list ordering reflects recent activity).
  Future<void> add(String gameId);

  /// Remove [gameId] from the favorites set. No-op if it isn't present.
  Future<void> remove(String gameId);

  /// Toggle helper — adds when missing, removes when present.
  /// Returns the new favorite state.
  Future<bool> toggle(String gameId);
}

class HiveFavoritesRepository implements FavoritesRepository {
  HiveFavoritesRepository(this._box);

  final Box<dynamic> _box;

  /// Open the favorites box. Call once at startup (Hive must be init'd).
  static Future<HiveFavoritesRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.favorites);
    return HiveFavoritesRepository(box);
  }

  @override
  List<String> getFavorites() {
    final raw = _box.get(HiveBoxes.favoritesKey);
    if (raw is! List) return const <String>[];
    return raw.whereType<String>().toList(growable: false);
  }

  @override
  bool isFavorite(String gameId) => getFavorites().contains(gameId);

  @override
  Future<void> add(String gameId) async {
    if (gameId.isEmpty) return;
    final current = getFavorites()..removeWhere((id) => id == gameId);
    current.insert(0, gameId);
    await _box.put(HiveBoxes.favoritesKey, current);
  }

  @override
  Future<void> remove(String gameId) async {
    final current = getFavorites()..removeWhere((id) => id == gameId);
    await _box.put(HiveBoxes.favoritesKey, current);
  }

  @override
  Future<bool> toggle(String gameId) async {
    if (isFavorite(gameId)) {
      await remove(gameId);
      return false;
    }
    await add(gameId);
    return true;
  }
}

class InMemoryFavoritesRepository implements FavoritesRepository {
  final List<String> _ids = <String>[];

  @override
  List<String> getFavorites() => List<String>.unmodifiable(_ids);

  @override
  bool isFavorite(String gameId) => _ids.contains(gameId);

  @override
  Future<void> add(String gameId) async {
    if (gameId.isEmpty) return;
    _ids.removeWhere((id) => id == gameId);
    _ids.insert(0, gameId);
  }

  @override
  Future<void> remove(String gameId) async {
    _ids.removeWhere((id) => id == gameId);
  }

  @override
  Future<bool> toggle(String gameId) async {
    if (isFavorite(gameId)) {
      await remove(gameId);
      return false;
    }
    await add(gameId);
    return true;
  }
}

/// Riverpod entry point for the favorites repository. Overridden in
/// `main.dart` with the Hive-backed implementation; tests override
/// with [InMemoryFavoritesRepository].
final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  throw UnimplementedError(
    'favoritesRepositoryProvider must be overridden in ProviderScope',
  );
});