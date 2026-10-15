import 'package:flutter/material.dart';

import '../game_widgets.dart';
import 'connect_lines_game.dart';
import 'maze_escape_game.dart';
import 'memory_cards_game.dart';
import 'memory_match_game.dart';
import 'spelling_bee_game.dart';
import 'sudoku_game.dart';
import 'tile_match_game.dart';
import 'typing_race_game.dart';
import 'water_sort_game.dart';

/// Facade for the Brain & Logic mini-games.
class LogicGames {
  LogicGames._();

  static Widget sudoku({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return SudokuGame(callbacks: callbacks);
  }

  static Widget waterSort({
    required MiniGameCallbacks callbacks,
    int level = 1,
    bool dailyChallenge = false,
  }) {
    return WaterSortGame(
      callbacks: callbacks,
      level: level,
      dailyChallenge: dailyChallenge,
    );
  }

  static Widget tileMatch({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return TileMatchGame(callbacks: callbacks);
  }

  static Widget connectLines({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return ConnectLinesGame(callbacks: callbacks);
  }

  static Widget memoryMatch({
    required MiniGameCallbacks callbacks,
    int level = 1,
    bool dailyChallenge = false,
  }) {
    return MemoryMatchGame(
      callbacks: callbacks,
      dailyChallenge: dailyChallenge,
    );
  }

  static Widget mazeEscape({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return MazeEscapeGame(callbacks: callbacks);
  }

  static Widget memoryCards({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return MemoryCardsGame(callbacks: callbacks, level: level);
  }

  static Widget typingRace({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return TypingRaceGame(callbacks: callbacks, level: level);
  }

  static Widget spellingBee({
    required MiniGameCallbacks callbacks,
    bool dailyChallenge = false,
  }) {
    return SpellingBeeGame(
      callbacks: callbacks,
      dailyChallenge: dailyChallenge,
    );
  }
}