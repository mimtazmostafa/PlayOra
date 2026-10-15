import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Persists the user's most recent search queries.
///
/// Two implementations:
/// - [HiveRecentSearchesRepository] — backed by Hive (production).
/// - [InMemoryRecentSearchesRepository] — for tests / previews.
///
/// The list is ordered most-recent-first and capped at [maxStored] entries.
/// Whitespace-only queries are normalized away and never stored.
abstract class RecentSearchesRepository {
  /// Maximum queries retained. Older entries are dropped when the cap is hit.
  static const int maxStored = 5;

  /// Returns the recent queries, most-recent first. Never includes blanks.
  List<String> getRecent();

  /// Push [query] to the front of the list. Duplicates are deduplicated so
  /// the same query floats to the top instead of appearing twice.
  Future<void> record(String query);

  /// Clear all stored queries.
  Future<void> clear();
}

class HiveRecentSearchesRepository implements RecentSearchesRepository {
  HiveRecentSearchesRepository(this._box);

  final Box<dynamic> _box;

  /// Open the recent-searches box. Call once at startup (Hive must be init'd).
  static Future<HiveRecentSearchesRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.recentSearches);
    return HiveRecentSearchesRepository(box);
  }

  @override
  List<String> getRecent() {
    final raw = _box.get(HiveBoxes.recentSearchesKey);
    if (raw is! List) return const <String>[];
    return raw.whereType<String>().toList(growable: false);
  }

  @override
  Future<void> record(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final current = getRecent()
      ..removeWhere((q) => q.toLowerCase() == normalized.toLowerCase());
    current.insert(0, normalized);
    if (current.length > RecentSearchesRepository.maxStored) {
      current.removeRange(
        RecentSearchesRepository.maxStored,
        current.length,
      );
    }
    await _box.put(HiveBoxes.recentSearchesKey, current);
  }

  @override
  Future<void> clear() async {
    await _box.put(HiveBoxes.recentSearchesKey, const <String>[]);
  }
}

class InMemoryRecentSearchesRepository implements RecentSearchesRepository {
  final List<String> _queries = <String>[];

  @override
  List<String> getRecent() => List<String>.unmodifiable(_queries);

  @override
  Future<void> record(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    _queries.removeWhere((q) => q.toLowerCase() == normalized.toLowerCase());
    _queries.insert(0, normalized);
    if (_queries.length > RecentSearchesRepository.maxStored) {
      _queries.removeRange(
        RecentSearchesRepository.maxStored,
        _queries.length,
      );
    }
  }

  @override
  Future<void> clear() async {
    _queries.clear();
  }
}
