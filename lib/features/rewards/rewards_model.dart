import 'dart:math' as math;

/// Pure data + level-curve math for the rewards system.
///
/// Kept independent of Hive / Riverpod so tests can drive the math
/// without any storage layer. The repository persists a snapshot;
/// this file decides what that snapshot means (e.g. how xp → level).
class RewardsSnapshot {
  const RewardsSnapshot({
    required this.coins,
    required this.xp,
  });

  /// Persistent coin count. Earned per game, never decays.
  final int coins;

  /// Lifetime XP. Drives level progression. Never decreases.
  final int xp;

  /// Empty / starter state. Equivalent to a brand-new install.
  static const RewardsSnapshot empty = RewardsSnapshot(coins: 0, xp: 0);

  RewardsSnapshot withCoins(int delta) =>
      RewardsSnapshot(coins: coins + delta, xp: xp);

  RewardsSnapshot withXp(int delta) =>
      RewardsSnapshot(coins: coins, xp: xp + delta);

  @override
  bool operator ==(Object other) =>
      other is RewardsSnapshot && other.coins == coins && other.xp == xp;

  @override
  int get hashCode => Object.hash(coins, xp);

  @override
  String toString() => 'RewardsSnapshot(coins: $coins, xp: $xp)';
}

/// Tunable knobs for the level curve. Centralized so the curve can
/// be re-tuned without touching the controller or widgets.
///
/// The curve is front-loaded on purpose: every early level is cheap,
/// so a player feels rewarded after a single game. As levels grow the
/// gap widens, so high levels still feel meaningful.
class RewardsCurve {
  const RewardsCurve({
    this.xpPerLevelBase = 50,
  });

  /// XP that defines the first jump from level 1 → 2. Higher = slower.
  /// `xp = xpPerLevelBase * (level - 1)^2` for `level >= 2`.
  final int xpPerLevelBase;

  /// The level that corresponds to a given xp total.
  ///   `level = floor(sqrt(xp / xpPerLevelBase)) + 1`
  /// With [xpPerLevelBase] = 50:
  ///   xp   0  → level 1
  ///   xp  49  → level 1
  ///   xp  50  → level 2
  ///   xp 199  → level 2
  ///   xp 200  → level 3
  ///   xp 449  → level 3
  ///   xp 450  → level 4
  ///   xp 800  → level 5
  ///   xp 1250 → level 6
  int levelFor(int xp) {
    if (xp <= 0) return 1;
    return math.sqrt(xp / xpPerLevelBase).floor() + 1;
  }

  /// The XP threshold at which [level] is reached. Inverse of [levelFor].
  ///   `xpToReach(L) = xpPerLevelBase * (L - 1)^2`
  int xpToReachLevel(int level) {
    if (level <= 1) return 0;
    final d = level - 1;
    return xpPerLevelBase * d * d;
  }

  /// XP required to go from [currentLevel] to [currentLevel + 1].
  /// For consecutive levels this is the difference of two squares.
  int xpToNextLevel(int currentLevel) {
    final a = currentLevel - 1;
    final b = currentLevel;
    return xpPerLevelBase * (b * b - a * a);
  }

  /// XP into the current level (clamped to [0, xpToNextLevel]).
  /// Used by progress bars in the UI.
  int xpIntoLevel(int xp, int currentLevel) {
    final base = xpToReachLevel(currentLevel);
    final cap = xpToNextLevel(currentLevel);
    final raw = xp - base;
    if (raw < 0) return 0;
    if (raw > cap) return cap;
    return raw;
  }

  /// 0..1 progress through the current level.
  double progressFor(int xp, int currentLevel) {
    final cap = xpToNextLevel(currentLevel);
    if (cap == 0) return 1;
    return (xpIntoLevel(xp, currentLevel) / cap).clamp(0.0, 1.0);
  }
}

/// Result of comparing two snapshots — used to fire level-up events.
class LevelDelta {
  const LevelDelta({
    required this.beforeLevel,
    required this.afterLevel,
  });

  final int beforeLevel;
  final int afterLevel;

  /// True when at least one level was crossed.
  bool get didLevelUp => afterLevel > beforeLevel;

  /// Every level crossed (in order). Empty when [didLevelUp] is false.
  /// `3 → 5` yields `(4, 5)` — one event per crossed level so the UI
  /// can fire multiple bursts in sequence if it wants.
  Iterable<int> get newLevels sync* {
    for (var l = beforeLevel + 1; l <= afterLevel; l++) {
      yield l;
    }
  }
}
