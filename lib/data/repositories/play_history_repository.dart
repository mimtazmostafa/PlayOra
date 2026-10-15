import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Persists per-game "last played" timestamps.
///
/// The achievements / profile screens need a stable record of *which*
/// games the player has played and *when* — neither of which is
/// captured by the existing rewards / streak boxes (those only hold
/// aggregate totals). Storage is intentionally minimal: one map at
/// [HiveBoxes.playHistoryKey] holding `{ gameId: isoTimestamp }` for
/// the most recent session of each game.
///
/// Two implementations:
/// - [HivePlayHistoryRepository] — backed by Hive (production).
/// - [InMemoryPlayHistoryRepository] — for tests / previews.
abstract class PlayHistoryRepository {
  /// Returns `{ gameId: lastPlayedAt }` for every game ever played.
  Map<String, DateTime> load();

  /// Persists [history] as the new source of truth.
  Future<void> save(Map<String, DateTime> history);

  /// Convenience: record [gameId] as played right now.
  Future<void> recordPlay(String gameId, {DateTime? at});
}

class HivePlayHistoryRepository implements PlayHistoryRepository {
  HivePlayHistoryRepository(this._box);

  final Box<dynamic> _box;

  /// Open the play-history box. Call once at startup (Hive must
  /// already be init'd via `HiveSetup.init`).
  static Future<HivePlayHistoryRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.playHistory);
    return HivePlayHistoryRepository(box);
  }

  @override
  Map<String, DateTime> load() {
    final raw = _box.get(HiveBoxes.playHistoryKey);
    if (raw is! Map) return <String, DateTime>{};
    final out = <String, DateTime>{};
    raw.forEach((key, value) {
      if (key is String && value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) out[key] = parsed;
      }
    });
    return out;
  }

  @override
  Future<void> save(Map<String, DateTime> history) async {
    final asStrings = <String, String>{
      for (final entry in history.entries)
        entry.key: entry.value.toIso8601String(),
    };
    await _box.put(HiveBoxes.playHistoryKey, asStrings);
  }

  @override
  Future<void> recordPlay(String gameId, {DateTime? at}) async {
    final current = load();
    current[gameId] = at ?? DateTime.now();
    await save(current);
  }
}

class InMemoryPlayHistoryRepository implements PlayHistoryRepository {
  Map<String, DateTime> _history = <String, DateTime>{};

  /// Test helper: seed the repo with a predefined history map.
  void seed(Map<String, DateTime> history) {
    _history = Map<String, DateTime>.from(history);
  }

  @override
  Map<String, DateTime> load() =>
      Map<String, DateTime>.unmodifiable(_history);

  @override
  Future<void> save(Map<String, DateTime> history) async {
    _history = Map<String, DateTime>.from(history);
  }

  @override
  Future<void> recordPlay(String gameId, {DateTime? at}) async {
    _history[gameId] = at ?? DateTime.now();
  }
}
