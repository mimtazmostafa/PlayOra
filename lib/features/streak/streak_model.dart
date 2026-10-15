/// Pure data + day-math for the play-streak feature.
///
/// Kept independent of Hive / Riverpod so tests can drive the day-gating
/// rules without spinning up storage. The repository persists a snapshot;
/// this file decides what that snapshot means (e.g. "yesterday → +1",
/// "today → no-op", "any other gap → reset to 1").
class StreakSnapshot {
  const StreakSnapshot({
    required this.count,
    required this.lastPlayDay,
  });

  /// Number of consecutive days with at least one recorded session.
  /// 0 means "no streak yet" — the empty / pre-first-play state.
  final int count;

  /// Last day a session was recorded, normalized to local midnight.
  /// Null when the user has never recorded a session.
  final DateTime? lastPlayDay;

  /// Empty / starter state — fresh install or post-reset.
  static const StreakSnapshot empty = StreakSnapshot(
    count: 0,
    lastPlayDay: null,
  );

  /// True when the user has never recorded a session.
  bool get isEmpty => count == 0 || lastPlayDay == null;

  StreakSnapshot withCount(int value) =>
      StreakSnapshot(count: value, lastPlayDay: lastPlayDay);

  StreakSnapshot withLastPlayDay(DateTime? value) =>
      StreakSnapshot(count: count, lastPlayDay: value);

  @override
  bool operator ==(Object other) =>
      other is StreakSnapshot &&
      other.count == count &&
      other.lastPlayDay == lastPlayDay;

  @override
  int get hashCode => Object.hash(count, lastPlayDay);

  @override
  String toString() =>
      'StreakSnapshot(count: $count, lastPlayDay: $lastPlayDay)';
}

/// Pure helpers that decide what happens to a streak when the user
/// plays on a given day. All methods are referentially transparent so
/// tests can pin a fake clock and assert the result directly.
class StreakMath {
  const StreakMath();

  /// Normalize [day] to local midnight. Two dates that share a
  /// calendar day in the device's timezone become equal.
  DateTime startOfDay(DateTime day) => DateTime(day.year, day.month, day.day);

  /// The new snapshot after recording a session on [now].
  ///
  /// Rules (today + lastPlayDay refer to the *local* day):
  ///   * `lastPlayDay == null` (first session ever) → count = 1.
  ///   * lastPlayDay == today (already counted today) → no-op.
  ///   * lastPlayDay == yesterday → count = previous + 1.
  ///   * anything else (gap of 2+ days) → count = 1 (start fresh).
  StreakSnapshot recordSession(StreakSnapshot current, DateTime now) {
    final today = startOfDay(now);
    final last = current.lastPlayDay;

    if (last == null) {
      return StreakSnapshot(count: 1, lastPlayDay: today);
    }

    final lastDay = startOfDay(last);

    // Same calendar day — already counted. No-op.
    if (lastDay == today) {
      return current;
    }

    final delta = today.difference(lastDay).inDays;

    if (delta == 1) {
      // Yesterday → extend streak by 1.
      return StreakSnapshot(
        count: current.count + 1,
        lastPlayDay: today,
      );
    }

    // Gap of two or more days (or a future-dated lastPlayDay, which
    // shouldn't happen but we treat as a reset for safety).
    return StreakSnapshot(count: 1, lastPlayDay: today);
  }
}
