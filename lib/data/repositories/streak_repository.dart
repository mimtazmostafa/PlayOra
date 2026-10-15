import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';
import '../../features/streak/streak_model.dart';

/// Persists the user's play-streak snapshot.
///
/// Two implementations:
/// - [HiveStreakRepository] — backed by Hive (production).
/// - [InMemoryStreakRepository] — for tests / previews.
///
/// Stored as a single record keyed by [HiveBoxes.streakKey] inside the
/// `streak` box. The record is a plain `Map<String, dynamic>` so it stays
/// backwards-compatible if the schema grows (e.g. adding a high-water
/// mark or longest-run field).
abstract class StreakRepository {
  /// Loads the current snapshot. Returns [StreakSnapshot.empty] when no
  /// record exists yet (fresh install).
  StreakSnapshot load();

  /// Writes [snapshot] to storage.
  Future<void> save(StreakSnapshot snapshot);
}

class HiveStreakRepository implements StreakRepository {
  HiveStreakRepository(this._box);

  final Box<dynamic> _box;

  /// Open the streak box. Call once at startup (Hive must be init'd).
  static Future<HiveStreakRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.streak);
    return HiveStreakRepository(box);
  }

  @override
  StreakSnapshot load() {
    final raw = _box.get(HiveBoxes.streakKey);
    if (raw is! Map) return StreakSnapshot.empty;
    final count = raw['count'];
    final lastPlayDay = raw['lastPlayDay'];
    return StreakSnapshot(
      count: count is int ? count : 0,
      lastPlayDay: lastPlayDay is String ? DateTime.tryParse(lastPlayDay) : null,
    );
  }

  @override
  Future<void> save(StreakSnapshot snapshot) async {
    await _box.put(HiveBoxes.streakKey, <String, dynamic>{
      'count': snapshot.count,
      'lastPlayDay': snapshot.lastPlayDay?.toIso8601String(),
    });
  }
}

class InMemoryStreakRepository implements StreakRepository {
  StreakSnapshot _snapshot = StreakSnapshot.empty;

  @override
  StreakSnapshot load() => _snapshot;

  @override
  Future<void> save(StreakSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
