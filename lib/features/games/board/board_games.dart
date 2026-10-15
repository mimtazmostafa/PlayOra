import 'package:flutter/material.dart';

import '../game_widgets.dart';
import 'backgammon_game.dart';
import 'chess_adapter_game.dart';
import 'dots_and_boxes_game.dart';
import 'four_in_a_row_game.dart';
import 'mini_carrom_game.dart';
import 'mini_ludo_game.dart';
import 'mini_pool_game.dart';
import 'minesweeper_game.dart';
import 'snake_ladders_game.dart';
import 'tic_tac_toe_game.dart';
import 'battleship_game.dart';

/// Facade for the Board / 2P mini-game pack.
class BoardGames {
  BoardGames._();

  static Widget ticTacToe({
    required MiniGameCallbacks callbacks,
    int level = 1,
    bool dailyChallenge = false,
  }) {
    return TicTacToeGame(
      callbacks: callbacks,
      level: level,
      dailyChallenge: dailyChallenge,
    );
  }

  static Widget fourInARow({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return FourInARowGame(callbacks: callbacks, level: level);
  }

  static Widget miniLudo({required MiniGameCallbacks callbacks}) {
    return MiniLudoGame(callbacks: callbacks);
  }

  static Widget miniCarrom({
    required bool twoPlayer,
    required MiniGameCallbacks callbacks,
  }) {
    return MiniCarromGame(twoPlayer: twoPlayer, callbacks: callbacks);
  }

  static Widget miniPool({required MiniGameCallbacks callbacks}) {
    return MiniPoolGame(callbacks: callbacks);
  }

  static Widget minesweeper({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return MinesweeperGame(callbacks: callbacks, level: level);
  }

  static Widget dotsAndBoxes({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return DotsAndBoxesGame(callbacks: callbacks, level: level);
  }

  static Widget snakeLadders({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return SnakeLaddersGame(callbacks: callbacks, level: level);
  }

  static Widget battleship({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return BattleshipGame(callbacks: callbacks, level: level);
  }

  static Widget chess({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return ChessAdapterGame(callbacks: callbacks, level: level);
  }

  static Widget backgammon({
    required MiniGameCallbacks callbacks,
    int level = 1,
  }) {
    return BackgammonGame(callbacks: callbacks, level: level);
  }
}