import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Persists the player's unlocked achievements.
///
/// Two implementations:
/// - [HiveAchievementsRepository] — backed by Hive (production).
/// - [InMemoryAchievementsRepository] — for tests / previews.
///
/// Storage shape: a single map at [HiveBoxes.unlockedKey] containing
/// `{ achievementId: iso8601Timestamp }`. We persist the unlock
/// timestamp (not just a bool) so the UI can show "Unlocked on Mar 5"
/// without needing to derive it elsewhere.
abstract class AchievementsRepository {
  /// Loads the current set of unlocked achievements as
  /// `{ id -> unlockedAt }`. Empty map when none have been unlocked.
  Map<String, DateTime> load();

  /// Persists [unlocked] as the new source of truth. Caller is
  /// expected to merge — the repo simply overwrites the whole map.
  Future<void> save(Map<String, DateTime> unlocked);
}

class HiveAchievementsRepository implements AchievementsRepository {
  HiveAchievementsRepository(this._box);

  final Box<dynamic> _box;

  /// Open the achievements box. Call once at startup (Hive must be
  /// init'd via `HiveSetup.init`).
  static Future<HiveAchievementsRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.achievements);
    return HiveAchievementsRepository(box);
  }

  @override
  Map<String, DateTime> load() {
    final raw = _box.get(HiveBoxes.unlockedKey);
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
  Future<void> save(Map<String, DateTime> unlocked) async {
    final asStrings = <String, String>{
      for (final entry in unlocked.entries) entry.key: entry.value.toIso8601String(),
    };
    await _box.put(HiveBoxes.unlockedKey, asStrings);
  }
}

class InMemoryAchievementsRepository implements AchievementsRepository {
  Map<String, DateTime> _unlocked = <String, DateTime>{};

  /// Test helper: seed the repo with a predefined unlock set, then
  /// build the controller. Mirrors the production "previously
  /// unlocked on prior sessions" shape.
  void seed(Map<String, DateTime> unlocked) {
    _unlocked = Map<String, DateTime>.from(unlocked);
  }

  @override
  Map<String, DateTime> load() => Map<String, DateTime>.unmodifiable(_unlocked);

  @override
  Future<void> save(Map<String, DateTime> unlocked) async {
    _unlocked = Map<String, DateTime>.from(unlocked);
  }
}
