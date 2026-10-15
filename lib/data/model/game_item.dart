import 'package:flutter/foundation.dart';

import '../models/game_model.dart';

/// UI-layer wrapper around [Game] that carries the *player progress*
/// the Home dashboard needs to render.
///
/// Why a separate class instead of adding fields to [Game]?
///
/// * `Game` is a pure catalog entity — identical across users.
///   Adding `level`/`highScore` would either force every caller to
///   supply fake values, or split "catalog game" from "played game"
///   awkwardly via nullable fields.
/// * The Home "Continue Playing" rail already needs the catalog game
///   *and* the player's current level / high-score. `GameItem` lets the
///   provider return a single, ready-to-render object.
///
/// Equality is value-based on (gameId, level, highScore) so the
/// continue-playing row can dedupe correctly when two play sessions
/// land on the same level.
@immutable
class GameItem {
  const GameItem({
    required this.game,
    required this.level,
    required this.highScore,
  });

  /// Builds a "fresh" item — no progress yet.
  const GameItem.fresh(Game game)
      : this(game: game, level: 1, highScore: 0);

  /// Catalog entity.
  final Game game;

  /// Current level (1-based). Used for the "Continue Playing" row.
  final int level;

  /// Lifetime high-score. Used for the "Continue Playing" row badge.
  final int highScore;

  /// Convenience accessors that delegate to [game] so call-sites read
  /// like normal [Game] usage.
  String get id => game.id;
  String get title => game.title;
  String get titleBangla => game.titleBangla;

  /// Progress fraction toward the next level — capped at 1.0. The
  /// bar on the card uses this directly.
  ///
  /// Linear model: every 5 levels is one full bar. Simple and easy
  /// to read in a glance.
  double get levelProgress {
    final remainder = level % 5;
    return remainder == 0 ? 1.0 : remainder / 5.0;
  }

  /// Visual progress label e.g. "Level 7" or "Score 12,400".
  String get progressLabel => 'Level $level';

  GameItem copyWith({Game? game, int? level, int? highScore}) {
    return GameItem(
      game: game ?? this.game,
      level: level ?? this.level,
      highScore: highScore ?? this.highScore,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GameItem &&
        other.game.id == game.id &&
        other.level == level &&
        other.highScore == highScore;
  }

  @override
  int get hashCode => Object.hash(game.id, level, highScore);

  @override
  String toString() =>
      'GameItem(id: ${game.id}, level: $level, highScore: $highScore)';
}
