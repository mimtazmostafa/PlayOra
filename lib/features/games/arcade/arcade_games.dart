import 'package:flutter/material.dart';

import '../game_widgets.dart';
import 'block_puzzle_game.dart';
import 'flappy_bird_game.dart';
import 'fruit_slice_game.dart';
import 'game_2048.dart';
import 'knife_hit_game.dart';
import 'lumberjack_battle_game.dart';
import 'pong_game.dart';
import 'snake_duel_game.dart';
import 'snake_game.dart';
import 'snake_master_game.dart';
import 'space_blast_game.dart';
import 'stack_tower_game.dart';
import 'subway_run_game.dart';
import 'tap_reaction_game.dart';
import 'tower_builder_game.dart';

/// Facade that maps mini-game ids to their widget constructors.
///
/// The dispatcher calls these instead of importing each game file
/// directly, which keeps imports flat and lets us swap
/// implementations in one place.
class ArcadeGames {
  ArcadeGames._();

  static Widget blockPuzzle({required MiniGameCallbacks callbacks}) {
    return BlockPuzzleGame(callbacks: callbacks);
  }

  static Widget snake({required MiniGameCallbacks callbacks}) {
    return SnakeGame(callbacks: callbacks);
  }

  static Widget snakeMaster({required MiniGameCallbacks callbacks}) {
    return SnakeMasterGame(callbacks: callbacks);
  }

  static Widget game2048({required MiniGameCallbacks callbacks}) {
    return Game2048Widget(callbacks: callbacks);
  }

  static Widget stackTower({required MiniGameCallbacks callbacks}) {
    return StackTowerGame(callbacks: callbacks);
  }

  static Widget tapReaction({required MiniGameCallbacks callbacks}) {
    return TapReactionGame(callbacks: callbacks);
  }

  static Widget flappyBird({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return FlappyBirdGame(callbacks: callbacks, level: level);
  }

  static Widget pong({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return PongGame(callbacks: callbacks, level: level);
  }

  static Widget snakeDuel({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return SnakeDuelGame(callbacks: callbacks, level: level);
  }

  static Widget lumberjackBattle({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return LumberjackBattleGame(callbacks: callbacks, level: level);
  }

  static Widget subwayRun({required MiniGameCallbacks callbacks}) {
    return SubwayRunGame(callbacks: callbacks);
  }

  static Widget spaceBlast({required MiniGameCallbacks callbacks}) {
    return SpaceBlastGame(callbacks: callbacks);
  }

  static Widget towerBuilder({required MiniGameCallbacks callbacks}) {
    return TowerBuilderGame(callbacks: callbacks);
  }

  static Widget knifeHit({required MiniGameCallbacks callbacks}) {
    return KnifeHitGame(callbacks: callbacks);
  }

  static Widget fruitSlice({
    required MiniGameCallbacks callbacks,
    bool dailyChallenge = false,
  }) {
    return FruitSliceGame(
      callbacks: callbacks,
      dailyChallenge: dailyChallenge,
    );
  }
}
