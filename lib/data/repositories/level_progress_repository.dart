import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Per-game level progression. Each game that supports level-by-level
/// play stores the highest unlocked level (1-indexed; level 1 is always
/// unlocked).
///
/// Data shape (stored inside [HiveBoxes.levelProgress]):
/// ```
/// { "<gameId>": <int highestUnlockedLevel> }
/// ```
/// The keys are exactly the [RegistryGame.id] slugs that the
/// dispatcher understands, so the level grid can be looked up directly
/// from a game id.
abstract class LevelProgressRepository {
  /// Highest level unlocked for [gameId]; always >= 1.
  int unlockedFor(String gameId);

  /// Total levels defined for [gameId] (the catalog decides this).
  int totalFor(String gameId);

  /// Mark [gameId] level [level] as completed; the next level becomes
  /// unlocked if it was not already.
  Future<void> markCompleted(String gameId, int level);

  /// Reset [gameId] back to level 1 (used by "play again" / debug).
  Future<void> reset(String gameId);

  /// Convenience: returns true iff [level] is currently playable.
  bool isUnlocked(String gameId, int level);
}

class HiveLevelProgressRepository implements LevelProgressRepository {
  HiveLevelProgressRepository(this._box);

  static const String _rootKey = 'progress';
  static const int _defaultTotal = 10;

  final Box<dynamic> _box;

  /// Open the level-progress box. Call once at startup.
  static Future<HiveLevelProgressRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.levelProgress);
    return HiveLevelProgressRepository(box);
  }

  Map<String, dynamic> _read() {
    final raw = _box.get(_rootKey);
    if (raw is Map) {
      return raw.cast<String, dynamic>();
    }
    return {};
  }

  Future<void> _write(Map<String, dynamic> map) async {
    await _box.put(_rootKey, map);
  }

  @override
  int unlockedFor(String gameId) {
    final map = _read();
    final raw = map[gameId];
    if (raw is int) {
      return raw < 1 ? 1 : raw;
    }
    return 1; // Level 1 is always unlocked for every game.
  }

  @override
  int totalFor(String gameId) {
    // 10 levels is the canonical default. Mini-games can override via
    // their own catalog if they need to expose more or fewer.
    final t = _GameLevelCatalog.totalLevelsFor(gameId);
    return t <= 0 ? _defaultTotal : t;
  }

  @override
  bool isUnlocked(String gameId, int level) {
    if (level < 1) return false;
    return level <= unlockedFor(gameId);
  }

  @override
  Future<void> markCompleted(String gameId, int level) async {
    if (level < 1) return;
    final map = _read();
    final cur = (map[gameId] as int?) ?? 1;
    final next = level + 1;
    if (next > cur) {
      map[gameId] = next;
      await _write(map);
    }
  }

  @override
  Future<void> reset(String gameId) async {
    final map = _read();
    map.remove(gameId);
    await _write(map);
  }
}

class InMemoryLevelProgressRepository implements LevelProgressRepository {
  final Map<String, int> _data = {};

  @override
  int unlockedFor(String gameId) => (_data[gameId] ?? 1).clamp(1, 9999);

  @override
  int totalFor(String gameId) {
    final t = _GameLevelCatalog.totalLevelsFor(gameId);
    return t <= 0 ? 10 : t;
  }

  @override
  bool isUnlocked(String gameId, int level) {
    if (level < 1) return false;
    return level <= unlockedFor(gameId);
  }

  @override
  Future<void> markCompleted(String gameId, int level) async {
    if (level < 1) return;
    final cur = _data[gameId] ?? 1;
    final next = level + 1;
    if (next > cur) _data[gameId] = next;
  }

  @override
  Future<void> reset(String gameId) async => _data.remove(gameId);
}

/// Per-game total level count. Mini-games with variable progression
/// (e.g. Connect Four, Tic-Tac-Toe) opt in here. Pure endless-score
/// games (Snake, 2048) report 0 → repository falls back to a 10-cell
/// grid so the picker still renders meaningfully.
class _GameLevelCatalog {
  static int totalLevelsFor(String gameId) {
    switch (gameId) {
      // Brain & logic — 10 stages each.
      case 'sudoku':
      case 'water-sort':
      case 'connect-lines':
      case 'memory-match':
      case 'maze-escape':
      case 'tile-match':
      case 'memory-cards':
      case 'typing-race':
        return 10;
      // Board — 10 stages.
      case 'tic-tac-toe':
      case 'four-in-a-row':
      case 'mini-ludo':
      case 'minesweeper':
      case 'dots-and-boxes':
      case 'snake-ladders':
      case 'snakes-and-ladders':
      case 'connect-four':
      case 'chess':
      case 'chess-master':
      case 'backgammon':
        return 10;
      // Sports — short innings.
      case 'cricket-batting':
        return 6;
      // Endless score games — fall back to 10.
      case 'snake':
      case 'game-2048':
      case 'stack-tower':
      case 'tap-reaction':
      case 'block-puzzle':
      case 'mini-pool':
      case 'mini-carrom':
      case 'battleship':
      case 'snake-duel':
      case 'lumberjack-battle':
      case 'lumberjack':
      case 'pong':
      case 'pong-classic':
      case 'flappy-bird':
      case 'flappy-bird-duel':
      case 'bomberman':
      case 'bomberman-classic':
      case 'pacman':
      case 'pacman-duel':
      case 'pac-man':
      case 'billiards':
      case 'billiards-8-ball':
      case 'pool-8':
        return 0;
      default:
        return 0;
    }
  }
}
