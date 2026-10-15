import 'package:flutter_test/flutter_test.dart';
import 'package:playnest/data/models/game_category.dart';
import 'package:playnest/data/models/game_difficulty.dart';
import 'package:playnest/data/models/game_model.dart';
import 'package:playnest/data/models/game_type.dart';
import 'package:playnest/data/repositories/game_repository.dart';

/// Tiny hand-rolled fixture so the tests don't depend on the bundled JSON.
List<Game> _fixture() => const [
      Game(
        id: 'sudoku-master',
        title: 'Sudoku Master',
        titleBangla: 'সুডোকু মাস্টার',
        category: GameCategory.puzzle,
        thumbnailAsset: 'assets/thumbnails/sudoku.png',
        description: 'Classic number puzzle with three difficulty levels.',
        difficulty: GameDifficulty.medium,
        avgSessionMinutes: 12,
        isOfflineAvailable: true,
        isFavorite: false,
        gameType: GameType.nativeFlutter,
        entryPoint: '/games/sudoku',
      ),
      Game(
        id: 'bubble-pop',
        title: 'Bubble Pop',
        titleBangla: 'বাবল পপ',
        category: GameCategory.arcade,
        thumbnailAsset: 'assets/thumbnails/bubble-pop.png',
        description: 'Tap to pop clusters of three or more bubbles.',
        difficulty: GameDifficulty.easy,
        avgSessionMinutes: 5,
        isOfflineAvailable: true,
        isFavorite: false,
        gameType: GameType.nativeFlutter,
        entryPoint: '/games/bubble-pop',
      ),
      Game(
        id: 'chess-master',
        title: 'Chess Master',
        titleBangla: 'দাবা মাস্টার',
        category: GameCategory.brain,
        thumbnailAsset: 'assets/thumbnails/chess.png',
        description: 'Play against adaptive AI across five ELO tiers.',
        difficulty: GameDifficulty.hard,
        avgSessionMinutes: 25,
        isOfflineAvailable: false,
        isFavorite: false,
        gameType: GameType.webview,
        entryPoint: 'https://playhub.bd/chess',
      ),
      Game(
        id: 'penalty-kick',
        title: 'Penalty Kick',
        titleBangla: 'পেনাল্টি কিক',
        category: GameCategory.sports,
        thumbnailAsset: 'assets/thumbnails/penalty-kick.png',
        description: 'Aim, power, and curve your way past the keeper.',
        difficulty: GameDifficulty.easy,
        avgSessionMinutes: 4,
        isOfflineAvailable: true,
        isFavorite: false,
        gameType: GameType.nativeFlutter,
        entryPoint: '/games/penalty-kick',
      ),
    ];

void main() {
  group('InMemoryGameRepository', () {
    late InMemoryGameRepository repo;
    final games = _fixture();

    setUp(() {
      repo = InMemoryGameRepository(games);
    });

    test('getAllGames returns the full list', () async {
      final all = await repo.getAllGames();
      expect(all, hasLength(4));
    });

    test('getByCategory returns only matching games', () async {
      final puzzle = await repo.getByCategory(GameCategory.puzzle);
      expect(puzzle, hasLength(1));
      expect(puzzle.first.id, 'sudoku-master');

      final brain = await repo.getByCategory(GameCategory.brain);
      expect(brain, hasLength(1));
      expect(brain.first.id, 'chess-master');

      final racing = await repo.getByCategory(GameCategory.racing);
      expect(racing, isEmpty);
    });

    test('getById returns the game or null', () async {
      final found = await repo.getById('chess-master');
      expect(found, isNotNull);
      expect(found!.title, 'Chess Master');

      final missing = await repo.getById('does-not-exist');
      expect(missing, isNull);
    });

    test('search matches the English title case-insensitively', () async {
      final hits = await repo.search('CHESS');
      expect(hits, hasLength(1));
      expect(hits.first.id, 'chess-master');
    });

    test('search matches the Bangla title', () async {
      final hits = await repo.search('সুডোকু');
      expect(hits, hasLength(1));
      expect(hits.first.id, 'sudoku-master');
    });

    test('search matches the description text', () async {
      final hits = await repo.search('keeper');
      expect(hits, hasLength(1));
      expect(hits.first.id, 'penalty-kick');
    });

    test('search with empty / whitespace query returns all games', () async {
      expect((await repo.search('')), hasLength(4));
      expect((await repo.search('   ')), hasLength(4));
    });
  });

  group('Game JSON round-trip', () {
    test('fromJson + toJson preserves every field', () {
      const original = Game(
        id: 'round-trip',
        title: 'Round Trip',
        titleBangla: 'রাউন্ড ট্রিপ',
        category: GameCategory.strategy,
        thumbnailAsset: 'assets/thumbnails/round-trip.png',
        description: 'Make sure every field survives the trip.',
        difficulty: GameDifficulty.hard,
        avgSessionMinutes: 30,
        isOfflineAvailable: false,
        isFavorite: true,
        gameType: GameType.webview,
        entryPoint: 'https://example.test/round-trip',
      );

      final decoded = Game.fromJson(original.toJson());
      expect(decoded, equals(original));
    });

    test('fromJson falls back gracefully on unknown enum values', () {
      final decoded = Game.fromJson(<String, dynamic>{
        'id': 'fallback',
        'title': 'Fallback',
        'category': 'a-category-that-does-not-exist',
        'difficulty': 'impossible',
        'gameType': 'flipbook',
      });
      expect(decoded.category, GameCategory.arcade);
      expect(decoded.difficulty, GameDifficulty.easy);
      expect(decoded.gameType, GameType.nativeFlutter);
      expect(decoded.avgSessionMinutes, 5);
      expect(decoded.isOfflineAvailable, isFalse);
      expect(decoded.isFavorite, isFalse);
      expect(decoded.title, 'Fallback');
      expect(decoded.titleBangla, '');
    });
  });
}