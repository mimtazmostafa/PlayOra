/// Pure data + deterministic-picking math for the daily-challenge
/// feature. Kept free of Hive / Riverpod so tests can drive the
/// "same day → same game, different day → different game" rule
/// without any storage.
class DailyChallenge {
  const DailyChallenge({
    required this.dayKey,
    required this.gameId,
    required this.targetScore,
    required this.bestScore,
    required this.isCompleted,
  });

  /// Calendar day in `YYYY-MM-DD` form (local time) that this
  /// challenge belongs to. The picker uses this as the seed.
  final String dayKey;

  /// Stable id of the game featured today.
  final String gameId;

  /// Score the user needs to hit to clear the challenge today.
  /// Targets scale with the difficulty of the picked game.
  final int targetScore;

  /// Highest score the user has scored *today* on the featured game.
  /// Persisted so a higher second attempt still counts.
  final int bestScore;

  /// True when the user has at least one run today with
  /// `score >= targetScore`.
  final bool isCompleted;

  /// A new challenge with [bestScore] replaced. Other fields unchanged.
  DailyChallenge withBestScore(int value) => DailyChallenge(
        dayKey: dayKey,
        gameId: gameId,
        targetScore: targetScore,
        bestScore: value,
        isCompleted: isCompleted,
      );

  /// A new challenge with [isCompleted] replaced.
  DailyChallenge withCompleted({required bool value, required int bestScore}) =>
      DailyChallenge(
        dayKey: dayKey,
        gameId: gameId,
        targetScore: targetScore,
        bestScore: bestScore,
        isCompleted: value,
      );

  @override
  bool operator ==(Object other) =>
      other is DailyChallenge &&
      other.dayKey == dayKey &&
      other.gameId == gameId &&
      other.targetScore == targetScore &&
      other.bestScore == bestScore &&
      other.isCompleted == isCompleted;

  @override
  int get hashCode =>
      Object.hash(dayKey, gameId, targetScore, bestScore, isCompleted);

  @override
  String toString() =>
      'DailyChallenge(dayKey: $dayKey, gameId: $gameId, '
      'target: $targetScore, best: $bestScore, completed: $isCompleted)';
}

/// Pure helpers for the daily challenge. The "picker" is deterministic:
/// given the same calendar day + same catalog, it always picks the
/// same game + target. Catalog rotation across days is achieved by
/// hashing the day-of-year into a 32-bit slot.
class DailyChallengeMath {
  const DailyChallengeMath();

  /// `YYYY-MM-DD` for [day], in the device's local timezone.
  String dayKey(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Stable 0..1 hash for a calendar day. Includes year so the picker
  /// rotates through the catalog even on the same month/day across
  /// different years.
  double dayHash(DateTime day) {
    // Combine year + day-of-year into a 32-bit int and divide.
    final doy = _dayOfYear(day);
    final seed = day.year * 1000 + doy;
    final mixed = (seed * 2654435761) & 0xFFFFFFFF;
    return mixed / 0xFFFFFFFF;
  }

  /// Index into [catalogIds] for [day]. Same day → same index.
  int indexForDay(DateTime day, int catalogLength) {
    if (catalogLength <= 0) return 0;
    final hash = dayHash(day);
    return (hash * catalogLength).floor().clamp(0, catalogLength - 1);
  }

  /// Look up the game id for today. Returns null when the catalog
  /// is empty.
  String? pickGameId(DateTime day, List<String> catalogIds) {
    if (catalogIds.isEmpty) return null;
    final i = indexForDay(day, catalogIds.length);
    return catalogIds[i];
  }

  /// Target score for [gameId] on [day]. Targets vary per game so
  /// easy games ask for more, harder games less — but stay stable
  /// for the day so the UI can show "Goal: 200" without flicker.
  ///
  /// Implementation: bucket the day-hash into 3 ranges (low/med/high
  /// target) so each game has 3 distinct daily targets.
  int targetFor(String gameId, DateTime day) {
    final hash = dayHash(day);
    final bucket = ((hash * 3).floor()) % 3; // 0, 1, 2
    final baseline = _baselineFor(gameId);
    // Multiply baseline by 1.0 / 0.75 / 1.5 for low / med / high.
    switch (bucket) {
      case 0:
        return (baseline * 0.75).round();
      case 1:
        return baseline;
      case 2:
      default:
        return (baseline * 1.5).round();
    }
  }

  /// Day-of-year, 1..366.
  int _dayOfYear(DateTime day) {
    final startOfYear = DateTime(day.year, 1, 1);
    final today = DateTime(day.year, day.month, day.day);
    return today.difference(startOfYear).inDays + 1;
  }

  /// Baseline target per game. Stable, deterministic, hash-based so
  /// every game has a different sweet-spot and the picker can stay
  /// generic.
  int _baselineFor(String gameId) {
    if (gameId.isEmpty) return 100;
    final h = gameId.hashCode & 0xFFFFFFFF;
    // Range 100..400 step 50 — keeps targets tidy and readable.
    final steps = (h ~/ 50) % 7; // 0..6
    return 100 + steps * 50;
  }
}