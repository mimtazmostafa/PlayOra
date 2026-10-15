import 'package:flutter/material.dart';

import '../models/game_category.dart';
import '../models/game_difficulty.dart';

/// Top-level grouping surfaced on the Home screen.
///
/// Four categories drive the Home rows. Each [RegistryGame] belongs
/// to exactly one, and the order in [GameRegistry.all] mirrors the
/// on-screen section order.
enum GameCollection {
  actionArcade('Action & Arcade'),
  casualFun('Casual & Fun'),
  matchPuzzles('Match & Puzzles'),
  sportsTargets('Sports & Targets');

  const GameCollection(this.label);
  final String label;
}

/// One entry in the central game registry.
///
/// Slimmer than [Game] (no asset / iconRecipe fields) because the
/// registry is what the **launcher** uses — the catalog layer
/// ([Game]) still exists for offline-mode metadata, search, etc.
@immutable
class RegistryGame {
  const RegistryGame({
    required this.id,
    required this.title,
    required this.titleBangla,
    required this.subtitle,
    required this.emoji,
    required this.category,
    required this.collection,
    required this.difficulty,
    required this.avgSessionMinutes,
    required this.isTwoPlayer,
    required this.routeName,
    required this.accentColor,
    this.featured = false,
    this.isNew = false,
    this.isPopular = false,
  });

  /// Stable id (slug).
  final String id;
  final String title;
  final String titleBangla;

  /// One-line tagline shown on cards.
  final String subtitle;

  /// Single emoji used as art placeholder — keeps the layout
  /// self-contained (no bitmap asset required).
  final String emoji;

  /// Catalog category (used for category-filtered screens).
  final GameCategory category;

  /// Which Home row this game belongs to.
  final GameCollection collection;

  /// Difficulty curve hint for the launcher UI.
  final GameDifficulty difficulty;

  /// Quick-Play bucket: 2 / 5 / 10 minutes.
  final int avgSessionMinutes;

  /// Whether the game supports 2-player Pass & Play.
  final bool isTwoPlayer;

  /// In-app router name the launcher uses to navigate.
  final String routeName;

  /// Card accent color (hex 0xAARRGGBB).
  final int accentColor;

  /// Surfaces this entry as the Featured "Game of the Day".
  final bool featured;

  /// Shows the bright red "NEW!" pill badge on the card.
  final bool isNew;

  /// Shows the cyan blue "MOST POPULAR!" pill badge on the card.
  final bool isPopular;

  Color get accent => Color(accentColor);
}

/// Central catalog of the PlayNest 20 mini-games.
///
/// Order in [all] is **significant** — it drives the Home screen
/// rendering order: the first 4 entries are surfaced as ACTION &
/// ARCADE, the next 3 as CASUAL & FUN, etc.
class GameRegistry {
  GameRegistry._();

  static const List<RegistryGame> all = <RegistryGame>[
    // ════════════════════════════════════════════════════════════
    // ACTION & ARCADE (7)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'racing-rush',
      title: 'Racing Rush',
      titleBangla: 'রেসিং রাশ',
      subtitle: 'Steer, nitro, collect coins',
      emoji: '🏎️',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/racing-rush',
      accentColor: 0xFFFF3B30, // Red car
      isNew: true,
    ),
    RegistryGame(
      id: 'basket-bounce',
      title: 'Basket Bounce',
      titleBangla: 'বাস্কেট বাউন্স',
      subtitle: 'Drag, aim, swish!',
      emoji: '🏀',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/basket-bounce',
      accentColor: 0xFFFB923C, // Orange ball
      isPopular: true,
    ),
    RegistryGame(
      id: 'soccer-hero',
      title: 'Soccer Hero',
      titleBangla: 'সকার হিরো',
      subtitle: 'Bend it like Beckham',
      emoji: '⚽',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/soccer-hero',
      accentColor: 0xFF22C55E, // Green
    ),
    RegistryGame(
      id: 'chess-master',
      title: 'Chess Master',
      titleBangla: 'দাবা মাস্টার',
      subtitle: 'Classic board game',
      emoji: '♟️',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.hard,
      avgSessionMinutes: 15,
      isTwoPlayer: true,
      routeName: '/game/chess-master',
      accentColor: 0xFF1F2937, // Slate 800
      isNew: true,
    ),
    RegistryGame(
      id: 'subway-run',
      title: 'Subway Run',
      titleBangla: 'সাবওয়ে রান',
      subtitle: 'Dodge trains, grab coins',
      emoji: '🏃',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/subway-run',
      accentColor: 0xFFF59E0B, // Amber
      isNew: true,
    ),

    // ════════════════════════════════════════════════════════════
    // CASUAL & FUN (3)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'space-blast',
      title: 'Space Blast',
      titleBangla: 'স্পেস ব্লাস্ট',
      subtitle: 'Blast alien waves',
      emoji: '🚀',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/space-blast',
      accentColor: 0xFFA073FF, // Pastel Purple
      isNew: true,
    ),
    RegistryGame(
      id: 'fruit-merge',
      title: 'Fruit Merge',
      titleBangla: 'ফ্রুট মার্জ',
      subtitle: 'Drop & merge to watermelon',
      emoji: '🍉',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/fruit-merge',
      accentColor: 0xFFEF5350, // Watermelon red
      isPopular: true,
    ),
    RegistryGame(
      id: 'tic-tac-toe',
      title: 'Tic Tac Toe',
      titleBangla: 'টিক-ট্যাক-টো',
      subtitle: 'Outsmart the AI or a friend',
      emoji: '⭕',
      category: GameCategory.brain,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 2,
      isTwoPlayer: true,
      routeName: '/game/tic-tac-toe',
      accentColor: 0xFF4FC3F7, // Slate blue
      isNew: true,
    ),
    RegistryGame(
      id: 'daily-fruit-slice',
      title: 'Fruit Slice · Daily',
      titleBangla: 'ফ্রুট স্লাইস · দৈনিক',
      subtitle: 'Today\'s seeded fruit wave.',
      emoji: '📅',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/daily-fruit-slice',
      accentColor: 0xFFFF6584, // Soft Coral
      isNew: true,
    ),
    RegistryGame(
      id: 'snake-master',
      title: 'Snake Master',
      titleBangla: 'স্নেক মাস্টার',
      subtitle: 'Eat, grow, dodge walls',
      emoji: '🐍',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/snake-master',
      accentColor: 0xFF30D158, // Vibrant Mint
    ),
    RegistryGame(
      id: 'daily-word-master',
      title: 'Word Master · Daily',
      titleBangla: 'ওয়ার্ড মাস্টার · দৈনিক',
      subtitle: 'One puzzle. Everyone plays the same.',
      emoji: '📅',
      category: GameCategory.brain,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/daily-word-master',
      accentColor: 0xFFF59E0B, // Amber
      isNew: true,
    ),
    RegistryGame(
      id: 'fruit-slice',
      title: 'Fruit Slice',
      titleBangla: 'ফ্রুট স্লাইস',
      subtitle: 'Swipe to slice, chain combos',
      emoji: '🍉',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/fruit-slice',
      accentColor: 0xFFFF6584, // Soft Coral
    ),
    RegistryGame(
      id: 'daily-tic-tac-toe',
      title: 'Tic Tac Toe · Daily',
      titleBangla: 'টিক-ট্যাক-টো · দৈনিক',
      subtitle: 'Today\'s AI opening.',
      emoji: '📅',
      category: GameCategory.brain,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 2,
      isTwoPlayer: false,
      routeName: '/game/daily-tic-tac-toe',
      accentColor: 0xFF4FC3F7, // Slate blue
      isNew: true,
    ),

    // ════════════════════════════════════════════════════════════
    // MATCH & PUZZLES (7)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'tile-match',
      title: 'Tile Match',
      titleBangla: 'টাইল ম্যাচ',
      subtitle: 'Match cute cat tiles',
      emoji: '🐱',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/tile-match',
      accentColor: 0xFFF472B6, // Pink
    ),
    RegistryGame(
      id: 'water-sort',
      title: 'Water Sort',
      titleBangla: 'ওয়াটার সর্ট',
      subtitle: 'Pour, sort, solve',
      emoji: '🧪',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/water-sort',
      accentColor: 0xFF7C3AED, // Violet
      isNew: true,
    ),
    RegistryGame(
      id: 'daily-water-sort',
      title: 'Water Sort · Daily',
      titleBangla: 'ওয়াটার সর্ট · দৈনিক',
      subtitle: 'Daily pour puzzle.',
      emoji: '💧',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/daily-water-sort',
      accentColor: 0xFF06B6D4, // Cyan
      isNew: true,
    ),
    RegistryGame(
      id: 'block-puzzle',
      title: 'Block Puzzle',
      titleBangla: 'ব্লক পাজল',
      subtitle: 'Drag blocks, clear lines',
      emoji: '🧩',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/block-puzzle',
      accentColor: 0xFF4C73FF, // Royal Soft Blue
    ),
    RegistryGame(
      id: 'candy-drop',
      title: 'Candy Drop',
      titleBangla: 'ক্যান্ডি ড্রপ',
      subtitle: 'Match 3+ candies',
      emoji: '🍭',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/candy-drop',
      accentColor: 0xFFFF6B9D, // Soft pink
      isNew: true,
    ),
    RegistryGame(
      id: 'daily-fruit-merge',
      title: 'Fruit Merge · Daily',
      titleBangla: 'ফ্রুট মার্জ · দৈনিক',
      subtitle: 'Today\'s seed fruit queue.',
      emoji: '📅',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/daily-fruit-merge',
      accentColor: 0xFFEF5350, // Watermelon red
      isNew: true,
    ),
    RegistryGame(
      id: 'memory-cards',
      title: 'Memory Cards',
      titleBangla: 'মেমরি কার্ডস',
      subtitle: 'Flip & match the pairs',
      emoji: '🎴',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/memory-cards',
      accentColor: 0xFF30D158, // Mint
    ),
    RegistryGame(
      id: 'balloon-pop',
      title: 'Balloon Pop',
      titleBangla: 'বেলুন পপ',
      subtitle: 'Pop, pop, pop!',
      emoji: '🎈',
      category: GameCategory.arcade,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 2,
      isTwoPlayer: false,
      routeName: '/game/balloon-pop',
      accentColor: 0xFF22D3EE, // Sky cyan
    ),
    RegistryGame(
      id: 'daily-balloon-pop',
      title: 'Balloon Pop · Daily',
      titleBangla: 'বেলুন পপ · দৈনিক',
      subtitle: 'Today\'s seeded balloon waves.',
      emoji: '📅',
      category: GameCategory.arcade,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 2,
      isTwoPlayer: false,
      routeName: '/game/daily-balloon-pop',
      accentColor: 0xFF22D3EE, // Sky cyan
      isNew: true,
    ),
    RegistryGame(
      id: 'jelly-jump',
      title: 'Jelly Jump',
      titleBangla: 'জেলি জাম্প',
      subtitle: 'Jump higher and reach the top!',
      emoji: '🍮',
      category: GameCategory.arcade,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/jelly-jump',
      accentColor: 0xFFA073FF, // Purple
    ),
    RegistryGame(
      id: 'tower-builder',
      title: 'Tower Builder',
      titleBangla: 'টাওয়ার বিল্ডার',
      subtitle: 'Stack it steady',
      emoji: '🏗️',
      category: GameCategory.arcade,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/tower-builder',
      accentColor: 0xFFFB923C, // Orange
    ),

    // ════════════════════════════════════════════════════════════
    // SPORTS & TARGETS (6)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'bubble-pop',
      title: 'Bubble Pop',
      titleBangla: 'বাবল পপ',
      subtitle: 'Aim & pop clusters',
      emoji: '🫧',
      category: GameCategory.arcade,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/bubble-pop',
      accentColor: 0xFF4C73FF, // Royal Blue
    ),
    RegistryGame(
      id: 'darts-club',
      title: 'Darts Club',
      titleBangla: 'ডার্টস ক্লাব',
      subtitle: 'Aim for bullseye',
      emoji: '🎯',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/darts-club',
      accentColor: 0xFFFF6584, // Coral
    ),
    RegistryGame(
      id: 'golf-star',
      title: 'Golf Star',
      titleBangla: 'গলফ স্টার',
      subtitle: 'Hit the ball into the hole with the fewest strokes!',
      emoji: '⛳',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/golf-star',
      accentColor: 0xFF30D158, // Mint
      isNew: true,
    ),
    RegistryGame(
      id: 'bowling-pro',
      title: 'Bowling Pro',
      titleBangla: 'বোলিং প্রো',
      subtitle: 'Roll for STRIKE!',
      emoji: '🎳',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/bowling-pro',
      accentColor: 0xFFFB923C, // Orange
    ),
    RegistryGame(
      id: 'knife-hit',
      title: 'Knife Hit',
      titleBangla: 'নাইফ হিট',
      subtitle: 'Stick the log',
      emoji: '🗡️',
      category: GameCategory.arcade,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/knife-hit',
      accentColor: 0xFFA855F7, // Purple
    ),
    RegistryGame(
      id: 'four-in-a-row',
      title: 'Connect Four',
      titleBangla: 'কানেক্ট ফোর',
      subtitle: 'Get 4 in a row — horizontally, vertically or diagonally!',
      emoji: '🔴',
      category: GameCategory.board,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: true,
      routeName: '/game/four-in-a-row',
      accentColor: 0xFF1E40AF, // Royal blue
      isNew: true,
    ),

    // ════════════════════════════════════════════════════════════
    // ACTION & ARCADE (additional — 6)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'treasure-hunt',
      title: 'Treasure Hunt',
      titleBangla: 'গুপ্তধন শিকার',
      subtitle: 'Find all the hidden treasures before time runs out!',
      emoji: '🗺️',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/treasure-hunt',
      accentColor: 0xFFF59E0B, // Amber
    ),
    RegistryGame(
      id: 'stack-tower',
      title: 'Stack Tower',
      titleBangla: 'টাওয়ার স্ট্যাক',
      subtitle: 'Stack the blocks as high as you can!',
      emoji: '🏢',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/stack-tower',
      accentColor: 0xFFFB923C, // Orange
    ),
    RegistryGame(
      id: 'flappy-bird',
      title: 'Flappy Bird',
      titleBangla: 'ফ্ল্যাপি বার্ড',
      subtitle: 'Fly through the pipes and get the highest score!',
      emoji: '🐦',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 2,
      isTwoPlayer: false,
      routeName: '/game/flappy-bird',
      accentColor: 0xFFFACC15, // Yellow
      isPopular: true,
    ),
    RegistryGame(
      id: 'snake-duel',
      title: 'Snake Duel',
      titleBangla: 'স্নেক ডুয়েল',
      subtitle: 'Outgrow your rival',
      emoji: '⚔️',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: true,
      routeName: '/game/snake-duel',
      accentColor: 0xFF30D158, // Mint
    ),
    RegistryGame(
      id: 'bomberman',
      title: 'Bomberman',
      titleBangla: 'বোম্বারম্যান',
      subtitle: 'Place bombs and defeat your enemies!',
      emoji: '🧨',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/bomberman',
      accentColor: 0xFFEF4444, // Red
      isNew: true,
    ),
    RegistryGame(
      id: 'pacman',
      title: 'Pac-Man',
      titleBangla: 'প্যাকম্যান',
      subtitle: 'Eat all the dots and avoid the ghosts!',
      emoji: '🟡',
      category: GameCategory.arcade,
      collection: GameCollection.actionArcade,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/pacman',
      accentColor: 0xFFFACC15, // Yellow
      isPopular: true,
    ),

    // ════════════════════════════════════════════════════════════
    // CASUAL & FUN (additional — 7)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'tap-reaction',
      title: 'Tap Reaction',
      titleBangla: 'ট্যাপ রিঅ্যাকশন',
      subtitle: 'Test your reflexes',
      emoji: '💥',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 2,
      isTwoPlayer: false,
      routeName: '/game/tap-reaction',
      accentColor: 0xFF22D3EE, // Cyan
    ),
    RegistryGame(
      id: 'pong',
      title: 'Pong',
      titleBangla: 'পং',
      subtitle: '1v1 paddle classic',
      emoji: '🏓',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 3,
      isTwoPlayer: true,
      routeName: '/game/pong',
      accentColor: 0xFFA073FF, // Pastel purple
    ),
    RegistryGame(
      id: 'lumberjack-battle',
      title: 'Lumberjack Battle',
      titleBangla: 'লাম্বারজ্যাক যুদ্ধ',
      subtitle: 'Chop in rhythm',
      emoji: '🪓',
      category: GameCategory.arcade,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/lumberjack-battle',
      accentColor: 0xFF8A5A00, // Brown
    ),
    RegistryGame(
      id: 'mini-ludo',
      title: 'Mini Ludo',
      titleBangla: 'মিনি লুডো',
      subtitle: 'Race tokens home',
      emoji: '🎲',
      category: GameCategory.board,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 8,
      isTwoPlayer: true,
      routeName: '/game/mini-ludo',
      accentColor: 0xFFEF4444, // Red
    ),
    RegistryGame(
      id: 'mini-carrom',
      title: 'Mini Carrom',
      titleBangla: 'মিনি ক্যারম',
      subtitle: 'Flick & pocket',
      emoji: '🥌',
      category: GameCategory.board,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 6,
      isTwoPlayer: true,
      routeName: '/game/mini-carrom',
      accentColor: 0xFFF59E0B, // Amber
    ),
    RegistryGame(
      id: 'snake-ladders',
      title: 'Snake & Ladders',
      titleBangla: 'সাপ-লাড্ডার',
      subtitle: 'Climb up, slide down',
      emoji: '🪜',
      category: GameCategory.board,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 8,
      isTwoPlayer: true,
      routeName: '/game/snake-ladders',
      accentColor: 0xFF22C55E, // Green
    ),
    RegistryGame(
      id: 'typing-race',
      title: 'Typing Race',
      titleBangla: 'টাইপিং রেস',
      subtitle: 'Type fast, win',
      emoji: '⌨️',
      category: GameCategory.brain,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/typing-race',
      accentColor: 0xFFFB923C, // Orange
    ),

    // ════════════════════════════════════════════════════════════
    // MATCH & PUZZLES (additional — 10)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'game-2048',
      title: '2048',
      titleBangla: '২০৪৮',
      subtitle: 'Slide & merge tiles',
      emoji: '🔢',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/game-2048',
      accentColor: 0xFFFACC15, // Yellow
      isPopular: true,
    ),
    RegistryGame(
      id: 'minesweeper',
      title: 'Minesweeper',
      titleBangla: 'মাইনসুইপার',
      subtitle: 'Avoid the mines',
      emoji: '💣',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 6,
      isTwoPlayer: false,
      routeName: '/game/minesweeper',
      accentColor: 0xFFEF4444, // Red
    ),
    RegistryGame(
      id: 'dots-and-boxes',
      title: 'Dots & Boxes',
      titleBangla: 'ডটস অ্যান্ড বক্সেস',
      subtitle: 'Out-chain your rival',
      emoji: '✏️',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: true,
      routeName: '/game/dots-and-boxes',
      accentColor: 0xFF4FC3F7, // Sky blue
    ),
    RegistryGame(
      id: 'battleship',
      title: 'Battleship',
      titleBangla: 'ব্যাটলশিপ',
      subtitle: 'Find & sink the fleet',
      emoji: '🚢',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 8,
      isTwoPlayer: false,
      routeName: '/game/battleship',
      accentColor: 0xFF1E40AF, // Royal blue
    ),
    RegistryGame(
      id: 'word-master',
      title: 'Word Master',
      titleBangla: 'ওয়ার্ড মাস্টার',
      subtitle: 'Tap letters, form a word',
      emoji: '📝',
      category: GameCategory.word,
      collection: GameCollection.casualFun,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/word-master',
      accentColor: 0xFF22D3EE, // Cyan
    ),
    RegistryGame(
      id: 'sudoku',
      title: 'Sudoku',
      titleBangla: 'সুডোকু',
      subtitle: 'Number placement',
      emoji: '9️⃣',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 10,
      isTwoPlayer: false,
      routeName: '/game/sudoku',
      accentColor: 0xFF4FC3F7, // Sky blue
    ),
    RegistryGame(
      id: 'connect-lines',
      title: 'Connect Lines',
      titleBangla: 'লাইন সংযোগ',
      subtitle: 'Flow-free puzzle',
      emoji: '➰',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/connect-lines',
      accentColor: 0xFFA073FF, // Purple
    ),
    RegistryGame(
      id: 'memory-match',
      title: 'Memory Match',
      titleBangla: 'মেমোরি ম্যাচ',
      subtitle: 'Flip & remember',
      emoji: '🧠',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/memory-match',
      accentColor: 0xFF4A1B9A, // Deep purple
    ),
    RegistryGame(
      id: 'daily-memory-match',
      title: 'Memory Match · Daily',
      titleBangla: 'মেমোরি ম্যাচ · দৈনিক',
      subtitle: 'Today\'s seeded tile layout.',
      emoji: '📅',
      category: GameCategory.brain,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/daily-memory-match',
      accentColor: 0xFF4A1B9A, // Deep purple
      isNew: true,
    ),
    RegistryGame(
      id: 'maze-escape',
      title: 'Maze Escape',
      titleBangla: 'মেয় এস্কেপ',
      subtitle: 'Find the exit, escape!',
      emoji: '🌀',
      category: GameCategory.puzzle,
      collection: GameCollection.matchPuzzles,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 3,
      isTwoPlayer: false,
      routeName: '/game/maze-escape',
      accentColor: 0xFF22D3EE, // Cyan
    ),

    // ════════════════════════════════════════════════════════════
    // SPORTS & TARGETS (additional — 3)
    // ════════════════════════════════════════════════════════════
    RegistryGame(
      id: 'mini-pool',
      title: 'Mini Pool',
      titleBangla: 'মিনি পুল',
      subtitle: 'Cue up, pocket the 5',
      emoji: '🎱',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 5,
      isTwoPlayer: false,
      routeName: '/game/mini-pool',
      accentColor: 0xFF22C55E, // Green
    ),
    RegistryGame(
      id: 'backgammon',
      title: 'Backgammon',
      titleBangla: 'ব্যাকগ্যামন',
      subtitle: 'Roll and race your checkers!',
      emoji: '🎰',
      category: GameCategory.board,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 12,
      isTwoPlayer: false,
      routeName: '/game/backgammon',
      accentColor: 0xFF8A5A00, // Brown
    ),
    RegistryGame(
      id: 'cricket-batting',
      title: 'Cricket Batting',
      titleBangla: 'ক্রিকেট ব্যাটিং',
      subtitle: 'Hit the ball, time your shot',
      emoji: '🏏',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 4,
      isTwoPlayer: false,
      routeName: '/game/cricket-batting',
      accentColor: 0xFF22C55E, // Green
    ),
    RegistryGame(
      id: 'billiards',
      title: 'Billiards 8-Ball',
      titleBangla: 'বিলিয়ার্ডস',
      subtitle: 'Sink the 8 ball, win 5 games!',
      emoji: '🎳',
      category: GameCategory.sports,
      collection: GameCollection.sportsTargets,
      difficulty: GameDifficulty.medium,
      avgSessionMinutes: 8,
      isTwoPlayer: false,
      routeName: '/game/billiards',
      accentColor: 0xFF1E40AF, // Royal blue felt
      isNew: true,
    ),
  ];

  // ───────── Accessors ─────────

  /// Lookup by [id]. Returns `null` for unknown ids.
  static RegistryGame? byId(String id) {
    for (final g in all) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Registry entries excluding the daily-challenge variants. Use this
  /// when iterating the catalog for launcher grids / carousels — daily
  /// challenges surface through [DailyChallengeCard] instead.
  static List<RegistryGame> get nonDaily =>
      all.where((g) => !g.id.startsWith('daily-')).toList(growable: false);

  /// Games in a single [GameCollection].
  static List<RegistryGame> inCollection(GameCollection collection) {
    return all.where((g) => g.collection == collection).toList(
          growable: false,
        );
  }

  /// Quick-Play buckets: 2 / 5 / 10 minutes.
  ///
  /// Each bucket picks every offline game whose `avgSessionMinutes`
  /// matches exactly, so the user's mental model ("I have 5 minutes")
  /// maps directly to a curated row.
  static List<RegistryGame> quickPlay(int minutes) {
    return all
        .where((g) => g.avgSessionMinutes == minutes)
        .toList(growable: false);
  }

  /// Games in a [GameCategory]. Used by the Categories tab.
  static List<RegistryGame> inCategory(GameCategory category) {
    return all.where((g) => g.category == category).toList(
          growable: false,
        );
  }

  /// The "Game of the Day" — first entry marked `featured: true`,
  /// or the first entry otherwise.
  static RegistryGame get gameOfTheDay {
    for (final g in all) {
      if (g.featured) return g;
    }
    return all.first;
  }
}
