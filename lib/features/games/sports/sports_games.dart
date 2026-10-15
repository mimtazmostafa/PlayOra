import 'package:flutter/material.dart';

import '../game_widgets.dart';
import 'bowling_pro_game.dart';
import 'cricket_batting_game.dart';
import 'golf_star_game.dart';
import 'soccer_hero_game.dart';

/// Facade for the Sports mini-game pack.
class SportsGames {
  SportsGames._();

  static Widget cricketBatting({required MiniGameCallbacks callbacks}) {
    return CricketBattingGame(callbacks: callbacks);
  }

  static Widget golfStar({required MiniGameCallbacks callbacks}) {
    return GolfStarGame(callbacks: callbacks);
  }

  static Widget bowlingPro({required MiniGameCallbacks callbacks}) {
    return BowlingProGame(callbacks: callbacks);
  }

  static Widget soccerHero({required MiniGameCallbacks callbacks}) {
    return SoccerHeroGame(callbacks: callbacks);
  }
}