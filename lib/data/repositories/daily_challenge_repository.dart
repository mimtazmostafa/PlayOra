import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';
import '../../features/daily_challenge/daily_challenge_model.dart';

/// Persists per-day completion + best score for the daily challenge.
///
/// Two implementations:
/// - [HiveDailyChallengeRepository] — backed by Hive (production).
/// - [InMemoryDailyChallengeRepository] — for tests / previews.
///
/// Records are keyed by `dayKey` (`YYYY-MM-DD`) inside the
/// `dailyChallenge` box. Each record holds `bestScore` + `isCompleted`.
/// The picker lives in [DailyChallengeMath]; this repo is a thin
/// storage layer.
abstract class DailyChallengeRepository {
  /// Load today's record by [dayKey], or null when there isn't one yet.
  DailyChallengeRecord? load(String dayKey);

  /// Save (or overwrite) [record] for its day.
  Future<void> save(DailyChallengeRecord record);
}

class DailyChallengeRecord {
  const DailyChallengeRecord({
    required this.dayKey,
    required this.bestScore,
    required this.isCompleted,
  });

  final String dayKey;
  final int bestScore;
  final bool isCompleted;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'bestScore': bestScore,
        'isCompleted': isCompleted,
      };

  static DailyChallengeRecord fromMap(String dayKey, Map<dynamic, dynamic> m) {
    return DailyChallengeRecord(
      dayKey: dayKey,
      bestScore: (m['bestScore'] is int) ? m['bestScore'] as int : 0,
      isCompleted: (m['isCompleted'] is bool) ? m['isCompleted'] as bool : false,
    );
  }
}

class HiveDailyChallengeRepository implements DailyChallengeRepository {
  HiveDailyChallengeRepository(this._box);

  final Box<dynamic> _box;

  static Future<HiveDailyChallengeRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.dailyChallenge);
    return HiveDailyChallengeRepository(box);
  }

  @override
  DailyChallengeRecord? load(String dayKey) {
    final raw = _box.get(dayKey);
    if (raw is! Map) return null;
    return DailyChallengeRecord.fromMap(dayKey, raw);
  }

  @override
  Future<void> save(DailyChallengeRecord record) async {
    await _box.put(record.dayKey, record.toMap());
  }
}

class InMemoryDailyChallengeRepository implements DailyChallengeRepository {
  final Map<String, DailyChallengeRecord> _records = <String, DailyChallengeRecord>{};

  @override
  DailyChallengeRecord? load(String dayKey) => _records[dayKey];

  @override
  Future<void> save(DailyChallengeRecord record) async {
    _records[record.dayKey] = record;
  }
}