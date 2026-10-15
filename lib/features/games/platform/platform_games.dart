import 'package:flutter/material.dart';

import '../game_widgets.dart';
import 'jelly_jump_game.dart';

/// Facade for the Platform mini-games.
class PlatformGames {
  PlatformGames._();

  static Widget jellyJump({required MiniGameCallbacks callbacks}) {
    return JellyJumpGame(callbacks: callbacks);
  }
}