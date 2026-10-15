import 'package:flutter/material.dart';

import '../../data/registry/game_registry.dart';
import '../games/arcade/arcade_games.dart';
import '../games/arcade/basket_bounce_game.dart';
import '../games/arcade/darts_club_game.dart';
import '../games/arcade/racing_rush_game.dart';
import '../games/arcade/treasure_hunt_game.dart';
import '../games/board/board_games.dart';
import '../games/game_widgets.dart';
import '../games/logic/bubble_pop_game.dart';
import '../games/logic/logic_games.dart';
import '../games/match/match_games.dart';
import '../games/platform/platform_games.dart';
import '../games/sports/sports_games.dart';
import 'billiards/billiards_game.dart';
import 'bomberman/bomberman_game.dart';
import 'pacman/pacman_game.dart';
// Note: fruit-slice, candy-drop, tic-tac-toe, memory-match, and
// balloon-pop are routed through ArcadeGames / LogicGames / MatchGames
// facades so the dispatcher stays flat.

/// Maps a [RegistryGame] to its actual mini-game widget.
///
/// Every mini-game is a leaf widget that takes a small, well-defined
/// callback interface — the dispatcher normalizes it so the
/// [GameContainerScreen] doesn't need to know the differences between
/// e.g. a snake game and a sudoku board.
class GamesDispatcher extends StatelessWidget {
  const GamesDispatcher({
    super.key,
    required this.game,
    required this.level,
    required this.paused,
    required this.soundOn,
    required this.hapticsOn,
    required this.onScoreChanged,
    required this.onStatsChanged,
    required this.onGameOver,
    required this.onHaptic,
  });

  final RegistryGame game;
  final int level;
  final bool paused;
  final bool soundOn;
  final bool hapticsOn;
  final ValueChanged<int> onScoreChanged;

  /// Per-game secondary stats surfaced through the host's HUD subtitle
  /// (e.g. "Moves 4", "Balls 3", "Shots 5"). Mini-games call this
  /// whenever a stat changes.
  final ValueChanged<String> onStatsChanged;

  final VoidCallback onGameOver;
  final ValueChanged<HapticFeedbackType> onHaptic;

  /// Adapter so mini-games that only know the legacy 3-callback
  /// interface can still report stats — we route stats through a
  /// closure that calls the host.
  MiniGameCallbacks _cbs() {
    return MiniGameCallbacks(
      onScoreChanged: onScoreChanged,
      onStatsChanged: onStatsChanged,
      onGameOver: onGameOver,
      onHaptic: onHaptic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pause wraps every game — short-circuits the entire tree without
    // asking each game to know about pause state.
    if (paused) {
      return const ColoredBox(color: Color(0xFF080B12));
    }

    final child = _resolve(game.id);
    return child;
  }

  Widget _resolve(String id) {
    switch (id) {
      // ─── Featured (Layer 1 ordering) ───
      case 'racing-rush':
        return RacingRushGame(callbacks: _cbs());
      case 'basket-bounce':
        return BasketBounceGame(callbacks: _cbs());
      case 'darts-club':
        return DartsClubGame(callbacks: _cbs());
      case 'fruit-slice':
        return ArcadeGames.fruitSlice(callbacks: _cbs());
      case 'daily-fruit-slice':
        return ArcadeGames.fruitSlice(
          callbacks: _cbs(),
          dailyChallenge: true,
        );
      case 'treasure-hunt':
        return TreasureHuntGame(callbacks: _cbs());

      // ─── Arcade / Popular ───
      case 'block-puzzle':
      case 'block-blast':
        return ArcadeGames.blockPuzzle(callbacks: _cbs());
      case 'snake-master':
      case 'snake':
      case 'snakes':
        return ArcadeGames.snake(callbacks: _cbs());
      case 'game-2048':
        return ArcadeGames.game2048(callbacks: _cbs());
      case 'stack-tower':
        return ArcadeGames.stackTower(callbacks: _cbs());
      case 'tap-reaction':
        return ArcadeGames.tapReaction(callbacks: _cbs());
      case 'flappy-bird':
      case 'flappy-bird-duel':
        return ArcadeGames.flappyBird(callbacks: _cbs(), level: level);
      case 'pong':
      case 'pong-classic':
        return ArcadeGames.pong(callbacks: _cbs(), level: level);
      case 'snake-duel':
        return ArcadeGames.snakeDuel(callbacks: _cbs(), level: level);
      case 'lumberjack-battle':
      case 'lumberjack':
        return ArcadeGames.lumberjackBattle(callbacks: _cbs(), level: level);

      // ─── Board / 2P ───
      case 'mini-ludo':
      case 'ludo-royale':
        return BoardGames.miniLudo(callbacks: _cbs());
      case 'mini-carrom':
      case 'mini-carrom-2p':
      case 'carrom-clash':
        return BoardGames.miniCarrom(
          twoPlayer: id == 'mini-carrom-2p',
          callbacks: _cbs(),
        );
      case 'mini-pool':
      case 'pool':
        return BoardGames.miniPool(callbacks: _cbs());
      case 'tic-tac-toe':
      case 'tictactoe':
        return BoardGames.ticTacToe(callbacks: _cbs());
      case 'daily-tic-tac-toe':
        return BoardGames.ticTacToe(
          callbacks: _cbs(),
          dailyChallenge: true,
        );
      case 'four-in-a-row':
        return BoardGames.fourInARow(callbacks: _cbs(), level: level);
      case 'minesweeper':
      case 'minesweeper-duel':
        return BoardGames.minesweeper(callbacks: _cbs(), level: level);
      case 'dots-and-boxes':
        return BoardGames.dotsAndBoxes(callbacks: _cbs(), level: level);
      case 'snake-ladders':
      case 'snakes-and-ladders':
        return BoardGames.snakeLadders(callbacks: _cbs(), level: level);
      case 'battleship':
        return BoardGames.battleship(callbacks: _cbs(), level: level);
      case 'chess':
      case 'chess-master':
      case 'chess-classic':
        return BoardGames.chess(callbacks: _cbs(), level: level);
      case 'backgammon':
      case 'backgammon-classic':
        return BoardGames.backgammon(callbacks: _cbs(), level: level);

      // ─── Bangladesh Hub ───
      case 'bangla-word-connect':
      case 'word-quest':
        return _BanglaFallback(
          title: 'Bangla Word Connect',
          callbacks: _cbs(),
        );
      case 'bangla-word-search':
        return _BanglaFallback(
          title: 'Bangla Word Search',
          callbacks: _cbs(),
        );
      case 'bangladesh-quiz':
        return _BanglaFallback(
          title: 'Bangladesh Quiz',
          callbacks: _cbs(),
        );

      // ─── Brain & Logic ───
      case 'sudoku':
      case 'sudoku-master':
        return LogicGames.sudoku(callbacks: _cbs(), level: level);
      case 'water-sort':
        return LogicGames.waterSort(callbacks: _cbs(), level: level);
      case 'daily-water-sort':
        return LogicGames.waterSort(
          callbacks: _cbs(),
          level: level,
          dailyChallenge: true,
        );
      case 'tile-match':
      case 'candy-crush-tile':
        return LogicGames.tileMatch(callbacks: _cbs(), level: level);
      case 'connect-lines':
        return LogicGames.connectLines(callbacks: _cbs(), level: level);
      case 'memory-match':
        return LogicGames.memoryMatch(callbacks: _cbs(), level: level);
      case 'daily-memory-match':
        return LogicGames.memoryMatch(
          callbacks: _cbs(),
          level: level,
          dailyChallenge: true,
        );
      case 'maze-escape':
        return LogicGames.mazeEscape(callbacks: _cbs(), level: level);
      case 'memory-cards':
        return LogicGames.memoryCards(callbacks: _cbs(), level: level);
      case 'typing-race':
        return LogicGames.typingRace(callbacks: _cbs(), level: level);

      // ─── Sports ───
      case 'cricket-batting':
      case 'cricket-clash':
        return SportsGames.cricketBatting(callbacks: _cbs());

      // ─── Bubble Shooter (route id from seed JSON) ───
      case 'bubble-pop':
        return BubblePopGame(callbacks: _cbs());

      // ─── 20-Game Catalog (Layer 3 new stubs) ───
      case 'subway-run':
        return ArcadeGames.subwayRun(callbacks: _cbs());
      case 'space-blast':
        return ArcadeGames.spaceBlast(callbacks: _cbs());
      case 'tower-builder':
        return ArcadeGames.towerBuilder(callbacks: _cbs());
      case 'knife-hit':
        return ArcadeGames.knifeHit(callbacks: _cbs());
      case 'word-master':
        return LogicGames.spellingBee(callbacks: _cbs());
      case 'daily-word-master':
        return LogicGames.spellingBee(
          callbacks: _cbs(),
          dailyChallenge: true,
        );
      case 'candy-drop':
        return MatchGames.candyDrop(callbacks: _cbs(), level: level);
      case 'daily-candy-drop':
        return MatchGames.candyDrop(
          callbacks: _cbs(),
          level: level,
          dailyChallenge: true,
        );
      case 'fruit-merge':
        return MatchGames.fruitMerge(callbacks: _cbs());
      case 'daily-fruit-merge':
        return MatchGames.fruitMerge(
          callbacks: _cbs(),
          dailyChallenge: true,
        );
      case 'balloon-pop':
        return MatchGames.balloonPop(callbacks: _cbs());
      case 'daily-balloon-pop':
        return MatchGames.balloonPop(
          callbacks: _cbs(),
          dailyChallenge: true,
        );
      case 'jelly-jump':
        return PlatformGames.jellyJump(callbacks: _cbs());
      case 'golf-star':
        return SportsGames.golfStar(callbacks: _cbs());
      case 'bowling-pro':
        return SportsGames.bowlingPro(callbacks: _cbs());
      case 'soccer-hero':
        return SportsGames.soccerHero(callbacks: _cbs());

      // ─── Bomberman (procedural) ───
      case 'bomberman':
      case 'bomberman-classic':
        return BombermanGame(callbacks: _cbs(), level: level);

      // ─── Pac-Man ───
      case 'pacman':
      case 'pacman-duel':
      case 'pac-man':
        return PacmanGame(callbacks: _cbs(), level: level);

      // ─── Billiards — full 2D-physics 8-ball rules. ───
      case 'billiards':
      case 'billiards-8-ball':
      case 'pool-8':
        return BilliardsGame(callbacks: _cbs(), level: level);

      // ─── Misc seed-only IDs that don't have a dedicated mini-game
      // yet — we render a polished "play this soon" stub rather than
      // throwing a "No game found" error. Every listed id routes to a
      // live, working screen — no broken navigation.
      default:
        return _InteractivePlaceholder(
          gameId: id,
          callbacks: _cbs(),
        );
    }
  }
}

/// Interactive placeholder for game IDs that don't have a dedicated
/// module yet. Keeps the launch experience honest — players can still
/// tap to rack up score, with no broken routes.
class _InteractivePlaceholder extends StatefulWidget {
  const _InteractivePlaceholder({
    required this.gameId,
    required this.callbacks,
  });

  final String gameId;
  final MiniGameCallbacks callbacks;

  @override
  State<_InteractivePlaceholder> createState() =>
      _InteractivePlaceholderState();
}

class _InteractivePlaceholderState extends State<_InteractivePlaceholder> {
  int _score = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.callbacks.onScoreChanged(_score);
    });
  }

  String _title() {
    final id = widget.gameId;
    return id
        .split('-')
        .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF00E887), Color(0xFF006B40)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E887).withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.sports_esports_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _title(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap anywhere to play',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () {
              setState(() => _score += 25);
              widget.callbacks.onScoreChanged(_score);
              widget.callbacks.onHaptic(HapticFeedbackType.selection);
            },
            icon: const Icon(Icons.touch_app_rounded),
            label: const Text('Tap to score'),
            style: FilledButton.styleFrom(
              backgroundColor: kGameAccent(),
              foregroundColor: const Color(0xFF00281A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Score: $_score',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight fallback for the Bangla-themed games (word connect,
/// word search, BD quiz). The full modules are scheduled but not yet
/// shipped; this stub keeps the catalog honest — players can play the
/// tap-to-score interaction while seeing the real title and a clear
/// "coming soon" hint.
class _BanglaFallback extends StatefulWidget {
  const _BanglaFallback({required this.title, required this.callbacks});
  final String title;
  final MiniGameCallbacks callbacks;

  @override
  State<_BanglaFallback> createState() => _BanglaFallbackState();
}

class _BanglaFallbackState extends State<_BanglaFallback> {
  int _score = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.callbacks.onScoreChanged(_score);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kGameBackground(Theme.of(context).brightness),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.translate_rounded, color: Colors.amber, size: 64),
          const SizedBox(height: 16),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coming soon — tap to score while we polish this one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () {
              setState(() => _score += 10);
              widget.callbacks.onScoreChanged(_score);
              widget.callbacks.onHaptic(HapticFeedbackType.selection);
            },
            icon: const Icon(Icons.touch_app_rounded),
            label: const Text('Tap to score'),
            style: FilledButton.styleFrom(
              backgroundColor: kGameAccent(),
              foregroundColor: const Color(0xFF00281A),
            ),
          ),
        ],
      ),
    );
  }
}
