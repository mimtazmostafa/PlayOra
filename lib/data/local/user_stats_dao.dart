// ignore_for_file: prefer_initializing_formals
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';
import '../../features/rewards/rewards_controller.dart';
import '../../features/streak/streak_controller.dart';

/// Per-game stats snapshot for the local cache.
///
/// All fields are denormalized into one record so the dashboard can
/// render without doing N reads against the play-history map. New
/// fields should be added here (and to the codec below) so the on-disk
/// shape stays self-describing.
class UserStatsRecord {
  const UserStatsRecord({
    required this.gameId,
    required this.highScore,
    required this.playCount,
    required this.totalXp,
    required this.lastPlayedAt,
  });

  final String gameId;
  final int highScore;
  final int playCount;
  final int totalXp;
  final DateTime? lastPlayedAt;

  static const UserStatsRecord empty = UserStatsRecord(
    gameId: '',
    highScore: 0,
    playCount: 0,
    totalXp: 0,
    lastPlayedAt: null,
  );

  UserStatsRecord copyWith({
    int? highScore,
    int? playCount,
    int? totalXp,
    DateTime? lastPlayedAt,
    bool clearLastPlayed = false,
  }) {
    return UserStatsRecord(
      gameId: gameId,
      highScore: highScore ?? this.highScore,
      playCount: playCount ?? this.playCount,
      totalXp: totalXp ?? this.totalXp,
      lastPlayedAt: clearLastPlayed
          ? null
          : (lastPlayedAt ?? this.lastPlayedAt),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'highScore': highScore,
        'playCount': playCount,
        'totalXp': totalXp,
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      };

  static UserStatsRecord fromMap(String gameId, Map<dynamic, dynamic> m) {
    return UserStatsRecord(
      gameId: gameId,
      highScore: (m['highScore'] is int) ? m['highScore'] as int : 0,
      playCount: (m['playCount'] is int) ? m['playCount'] as int : 0,
      totalXp: (m['totalXp'] is int) ? m['totalXp'] as int : 0,
      lastPlayedAt: (m['lastPlayedAt'] is String)
          ? DateTime.tryParse(m['lastPlayedAt'] as String)
          : null,
    );
  }
}

/// Aggregate stats for the dashboard.
///
/// Sums across every per-game [UserStatsRecord]. Computed on demand so
/// adding a new per-game field doesn't require us to keep an aggregate
/// in sync.
class UserStatsSummary {
  const UserStatsSummary({
    required this.totalGamesPlayed,
    required this.totalHighScores,
    required this.totalXp,
    required this.totalSessions,
    required this.bestGame,
    required this.recentGame,
  });

  /// Number of distinct games the player has launched at least once.
  final int totalGamesPlayed;

  /// Sum of [UserStatsRecord.highScore] across every game.
  final int totalHighScores;

  /// Sum of [UserStatsRecord.totalXp] across every game.
  final int totalXp;

  /// Sum of [UserStatsRecord.playCount] across every game — i.e. total
  /// sessions played (a single play can count against several games).
  final int totalSessions;

  /// The game with the highest [UserStatsRecord.highScore], or null
  /// when the player hasn't played anything yet.
  final String? bestGame;

  /// Most recently played gameId (by [UserStatsRecord.lastPlayedAt]),
  /// or null when there's no history.
  final String? recentGame;

  static const UserStatsSummary empty = UserStatsSummary(
    totalGamesPlayed: 0,
    totalHighScores: 0,
    totalXp: 0,
    totalSessions: 0,
    bestGame: null,
    recentGame: null,
  );
}

/// DAO-style read/write surface for per-game user stats.
///
/// In a Room-migration world this would be a `@Dao` interface with
/// `@Query` and `@Insert`/`@Update` methods. We replicate that shape on
/// top of Hive so the call sites stay simple and the storage backend
/// can be swapped without rewriting the controllers.
abstract class UserStatsDao {
  /// Per-game stats keyed by gameId.
  Map<String, UserStatsRecord> loadAll();

  /// Stats for a single game, or [UserStatsRecord.empty] when missing.
  UserStatsRecord loadOne(String gameId);

  /// Atomically apply a finished session:
  ///   * increment [gameId]'s play count
  ///   * update the high score if [score] beats the previous best
  ///   * add [xpEarned] to the lifetime XP total
  ///   * stamp [gameId] as just-played at [at] (defaults to now)
  ///
  /// Returns the post-write [UserStatsRecord] as it lives on disk.
  Future<UserStatsRecord> recordSession({
    required String gameId,
    required int score,
    required int xpEarned,
    DateTime? at,
  });

  /// Aggregate dashboard summary. See [UserStatsSummary].
  UserStatsSummary summarize();

  /// Wipe every per-game record. Used by tests and the upcoming
  /// "reset progress" debug action.
  Future<void> reset();
}

/// Hive-backed [UserStatsDao] implementation.
///
/// Records are stored in two places (mirroring the existing
/// play-history repository so we don't have to migrate data when this
/// DAO is wired up):
///   * [HiveBoxes.playHistory] — `last_played` map keyed by gameId,
///                                used as the source of [lastPlayedAt].
///   * [HiveBoxes.userProfile] — `user_stats` map keyed by gameId,
///                                holding per-game {highScore, playCount,
///                                totalXp}.
///   * [HiveBoxes.gameLibrary] — placeholder for any catalog-level
///                                aggregate we may want later (kept as
///                                a constructor param to keep the
///                                facade's box list symmetric).
///   * [HiveBoxes.appSettings] — kept as a constructor arg so future
///                                global stats (totals cache) have a
///                                place to live.
class HiveUserStatsDao implements UserStatsDao {
  HiveUserStatsDao({
    required Box<dynamic> playHistory,
    required Box<dynamic> userProfile,
    // Reserved for future global-aggregate fields; ignored at the moment
    // but accepted so the [GameDatabase] facade can wire all four boxes
    // up-front.
    // ignore: unused_field
    required Box<dynamic> gameLibrary,
    // ignore: unused_field
    required Box<dynamic> appSettings,
  })  : _playHistory = playHistory,
        _userProfile = userProfile,
        _gameLibrary = gameLibrary,
        _appSettings = appSettings;

  final Box<dynamic> _playHistory;
  final Box<dynamic> _userProfile;
  // Reserved for future global-aggregate fields; ignored at the moment
  // but accepted so the [GameDatabase] facade can wire all four boxes
  // up-front.
  // ignore: unused_field
  final Box<dynamic>? _gameLibrary;
  // ignore: unused_field
  final Box<dynamic>? _appSettings;

  /// Key inside [HiveBoxes.userProfile] holding the per-game map.
  static const String _statsKey = 'user_stats';

  /// Key inside [HiveBoxes.playHistory] holding `{ gameId: isoTimestamp }`.
  /// Mirrors [HivePlayHistoryRepository.playHistoryKey] — we read it
  /// directly so the DAO and the history repo stay consistent.
  static const String _lastPlayedKey = 'last_played';

  Map<String, UserStatsRecord> _decodeStats(Box<dynamic> box) {
    final raw = box.get(_statsKey);
    if (raw is! Map) return <String, UserStatsRecord>{};
    final out = <String, UserStatsRecord>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        out[key] = UserStatsRecord.fromMap(key, value);
      }
    });
    return out;
  }

  Map<String, String> _encodeStats(Map<String, UserStatsRecord> records) {
    return <String, String>{
      // Hive's typed boxes accept String keys via the toMap output of
      // each record; we wrap them so the dynamic store stays readable.
      for (final entry in records.entries)
        entry.key: entry.value.toMap().toString(),
    };
  }

  @override
  Map<String, UserStatsRecord> loadAll() {
    final out = _decodeStats(_userProfile);
    final lastPlayedRaw = _playHistory.get(_lastPlayedKey);
    if (lastPlayedRaw is! Map) return out;
    lastPlayedRaw.forEach((key, value) {
      if (key is String && value is String) {
        final stamp = DateTime.tryParse(value);
        if (stamp == null) return;
        final existing = out[key] ??
            UserStatsRecord(
              gameId: key,
              highScore: 0,
              playCount: 0,
              totalXp: 0,
              lastPlayedAt: stamp,
            );
        out[key] = existing.copyWith(lastPlayedAt: stamp);
      }
    });
    return out;
  }

  @override
  UserStatsRecord loadOne(String gameId) {
    final all = loadAll();
    return all[gameId] ??
        UserStatsRecord(
          gameId: gameId,
          highScore: 0,
          playCount: 0,
          totalXp: 0,
          lastPlayedAt: null,
        );
  }

  @override
  Future<UserStatsRecord> recordSession({
    required String gameId,
    required int score,
    required int xpEarned,
    DateTime? at,
  }) async {
    final stamp = at ?? DateTime.now();
    final all = _decodeStats(_userProfile);
    final current = all[gameId] ??
        UserStatsRecord(
          gameId: gameId,
          highScore: 0,
          playCount: 0,
          totalXp: 0,
          lastPlayedAt: null,
        );
    final nextHigh = score > current.highScore ? score : current.highScore;
    final updated = current.copyWith(
      highScore: nextHigh,
      playCount: current.playCount + 1,
      totalXp: current.totalXp + (xpEarned > 0 ? xpEarned : 0),
      lastPlayedAt: stamp,
    );
    all[gameId] = updated;
    await _userProfile.put(_statsKey, _encodeStats(all));

    // Mirror the timestamp into the play-history box so the existing
    // PlayHistoryRepository / HomeScreen "Continue playing" lists keep
    // working without a second source of truth.
    final rawHistory = _playHistory.get(_lastPlayedKey);
    final next = <String, String>{
      if (rawHistory is Map)
        for (final entry in rawHistory.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
    };
    next[gameId] = stamp.toIso8601String();
    await _playHistory.put(_lastPlayedKey, next);

    return updated;
  }

  @override
  UserStatsSummary summarize() {
    final all = loadAll();
    if (all.isEmpty) return UserStatsSummary.empty;

    var totalHigh = 0;
    var totalXp = 0;
    var totalSessions = 0;
    String? bestId;
    var bestScore = -1;
    String? recentId;
    DateTime? recentStamp;

    all.forEach((id, rec) {
      totalHigh += rec.highScore;
      totalXp += rec.totalXp;
      totalSessions += rec.playCount;
      if (rec.highScore > bestScore) {
        bestScore = rec.highScore;
        bestId = id;
      }
      final stamp = rec.lastPlayedAt;
      if (stamp != null) {
        final rs = recentStamp;
        if (rs == null || stamp.isAfter(rs)) {
          recentStamp = stamp;
          recentId = id;
        }
      }
    });

    return UserStatsSummary(
      totalGamesPlayed: all.length,
      totalHighScores: totalHigh,
      totalXp: totalXp,
      totalSessions: totalSessions,
      bestGame: bestId,
      recentGame: recentId,
    );
  }

  @override
  Future<void> reset() async {
    await _userProfile.put(_statsKey, <String, String>{});
  }
}

/// In-memory [UserStatsDao] for tests and Storybook previews.
///
/// Behaves exactly like [HiveUserStatsDao] but doesn't touch any box.
/// Tests can seed via [seed].
class InMemoryUserStatsDao implements UserStatsDao {
  final Map<String, UserStatsRecord> _records = <String, UserStatsRecord>{};

  void seed(Map<String, UserStatsRecord> records) {
    _records
      ..clear()
      ..addAll(records);
  }

  @override
  Map<String, UserStatsRecord> loadAll() =>
      Map<String, UserStatsRecord>.unmodifiable(_records);

  @override
  UserStatsRecord loadOne(String gameId) =>
      _records[gameId] ??
      UserStatsRecord(
        gameId: gameId,
        highScore: 0,
        playCount: 0,
        totalXp: 0,
        lastPlayedAt: null,
      );

  @override
  Future<UserStatsRecord> recordSession({
    required String gameId,
    required int score,
    required int xpEarned,
    DateTime? at,
  }) async {
    final stamp = at ?? DateTime.now();
    final current = loadOne(gameId);
    final updated = current.copyWith(
      highScore: score > current.highScore ? score : current.highScore,
      playCount: current.playCount + 1,
      totalXp: current.totalXp + (xpEarned > 0 ? xpEarned : 0),
      lastPlayedAt: stamp,
    );
    _records[gameId] = updated;
    return updated;
  }

  @override
  UserStatsSummary summarize() {
    if (_records.isEmpty) return UserStatsSummary.empty;
    var totalHigh = 0;
    var totalXp = 0;
    var totalSessions = 0;
    String? bestId;
    var bestScore = -1;
    String? recentId;
    DateTime? recentStamp;
    _records.forEach((id, rec) {
      totalHigh += rec.highScore;
      totalXp += rec.totalXp;
      totalSessions += rec.playCount;
      if (rec.highScore > bestScore) {
        bestScore = rec.highScore;
        bestId = id;
      }
      final stamp = rec.lastPlayedAt;
      if (stamp != null) {
        final rs = recentStamp;
        if (rs == null || stamp.isAfter(rs)) {
          recentStamp = stamp;
          recentId = id;
        }
      }
    });
    return UserStatsSummary(
      totalGamesPlayed: _records.length,
      totalHighScores: totalHigh,
      totalXp: totalXp,
      totalSessions: totalSessions,
      bestGame: bestId,
      recentGame: recentId,
    );
  }

  @override
  Future<void> reset() async {
    _records.clear();
  }
}

/// Riverpod entry point for the [UserStatsDao]. Overridden in `main.dart`
/// with the Hive-backed impl wired in via the [GameDatabase] facade.
/// Tests override with [InMemoryUserStatsDao].
final userStatsDaoProvider = Provider<UserStatsDao>((ref) {
  throw UnimplementedError(
    'userStatsDaoProvider must be overridden in ProviderScope',
  );
});

/// Reactive view of the [UserStatsSummary] aggregate.
///
/// Watches the DAO's [summarize] on every build so a freshly-completed
/// session (which updates [userStatsDaoProvider]) is reflected the next
/// time the More tab comes into focus. Also touches the rewards +
/// streak controllers so the screen re-runs the summary when those
/// change.
final userStatsSummaryProvider = Provider<UserStatsSummary>((ref) {
  ref.watch(rewardsControllerProvider);
  ref.watch(streakControllerProvider);
  final dao = ref.watch(userStatsDaoProvider);
  return dao.summarize();
});
