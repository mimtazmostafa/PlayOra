import 'package:flutter/material.dart';

import '../game_widgets.dart';
import '../logic/memory_cards_game.dart';
import 'balloon_pop_game.dart';
import 'candy_drop_game.dart';
import 'fruit_merge_game.dart';

/// Facade for the Match & Puzzles mini-games.
class MatchGames {
  MatchGames._();

  static Widget candyDrop({
    required MiniGameCallbacks callbacks,
    int level = 1,
    bool dailyChallenge = false,
  }) {
    return CandyDropGame(
      callbacks: callbacks,
      level: level,
      dailyChallenge: dailyChallenge,
    );
  }

  static Widget fruitMerge({
    required MiniGameCallbacks callbacks,
    bool dailyChallenge = false,
  }) {
    return FruitMergeGame(
      callbacks: callbacks,
      dailyChallenge: dailyChallenge,
    );
  }

  static Widget memoryCards({required MiniGameCallbacks callbacks}) {
    return MemoryCardsGame(callbacks: callbacks);
  }

  static Widget balloonPop({
    required MiniGameCallbacks callbacks,
    bool dailyChallenge = false,
  }) {
    return BalloonPopGame(
      callbacks: callbacks,
      dailyChallenge: dailyChallenge,
    );
  }
}
