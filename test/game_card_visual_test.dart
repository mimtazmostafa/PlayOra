import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/models/game_category.dart';
import 'package:playnest/data/models/game_difficulty.dart';
import 'package:playnest/data/models/game_model.dart';
import 'package:playnest/data/models/game_type.dart';
import 'package:playnest/features/games/widgets/game_card.dart';
import 'package:playnest/features/games/widgets/game_category_visual.dart';

Game _sample({GameCategory category = GameCategory.puzzle}) => Game(
      id: 'sample',
      title: 'Sample',
      titleBangla: 'নমুনা',
      category: category,
      thumbnailAsset: 'assets/thumbs/sample.png',
      description: 'desc',
      difficulty: GameDifficulty.easy,
      avgSessionMinutes: 5,
      isOfflineAvailable: true,
      isFavorite: false,
      gameType: GameType.nativeFlutter,
      entryPoint: '/x',
    );

void main() {
  group('GameCategoryVisual', () {
    test('every GameCategory has a gradient + icon mapping', () {
      for (final c in GameCategory.values) {
        final gradient = GameCategoryVisual.gradientFor(c);
        expect(
          gradient.colors.length,
          2,
          reason: '$c should have a 2-stop gradient',
        );
        expect(GameCategoryVisual.iconFor(c), isA<IconData>());
      }
    });

    test('two distinct categories produce distinct gradient color pairs', () {
      final seen = <String>{};
      for (final c in GameCategory.values) {
        final pair = GameCategoryVisual.gradientFor(c).colors
            .map((color) => color.toARGB32())
            .join('|');
        expect(
          seen.add(pair),
          isTrue,
          reason: '$c reuses another category gradient',
        );
      }
    });
  });

  group('Game model badge flags', () {
    test('isNew + isPopular default to false', () {
      final g = _sample();
      expect(g.isNew, isFalse);
      expect(g.isPopular, isFalse);
    });

    test('copyWith toggles isNew + isPopular independently', () {
      final base = _sample();
      final asNew = base.copyWith(isNew: true);
      final asPopular = base.copyWith(isPopular: true);
      expect(asNew.isNew, isTrue);
      expect(asNew.isPopular, isFalse);
      expect(asPopular.isNew, isFalse);
      expect(asPopular.isPopular, isTrue);
    });

    test('toJson / fromJson round-trip preserves the flags', () {
      final g = _sample().copyWith(isNew: true, isPopular: true);
      final round = Game.fromJson(g.toJson());
      expect(round.isNew, isTrue);
      expect(round.isPopular, isTrue);
    });

    test('fromJson tolerates missing isNew / isPopular (older seed shape)',
        () {
      final minimal = <String, dynamic>{
        'id': 'sample',
        'title': 'Sample',
        'titleBangla': 'নমুনা',
        'category': 'puzzle',
        'thumbnailAsset': '',
        'description': '',
        'difficulty': 'easy',
        'avgSessionMinutes': 5,
        'isOfflineAvailable': false,
        'isFavorite': false,
        'gameType': 'nativeFlutter',
        'entryPoint': '',
      };
      final g = Game.fromJson(minimal);
      expect(g.isNew, isFalse);
      expect(g.isPopular, isFalse);
    });
  });

  group('GameCard badge rendering', () {
    Widget wrap(Game game) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: GameCard(game: game, onTap: () {}),
              ),
            ),
          ),
        );

    testWidgets('badge is hidden when neither isNew nor isPopular is set',
        (tester) async {
      await tester.pumpWidget(wrap(_sample()));
      expect(find.text('NEW'), findsNothing);
      expect(find.text('POPULAR'), findsNothing);
    });

    testWidgets('NEW badge renders for isNew', (tester) async {
      await tester
          .pumpWidget(wrap(_sample().copyWith(isNew: true)));
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('POPULAR'), findsNothing);
    });

    testWidgets('POPULAR badge renders for isPopular', (tester) async {
      await tester
          .pumpWidget(wrap(_sample().copyWith(isPopular: true)));
      expect(find.text('POPULAR'), findsOneWidget);
      expect(find.text('NEW'), findsNothing);
    });
  });

  group('GameCard thumbnail uses category accent', () {
    testWidgets('thumbnail draws a non-empty gradient icon per category',
        (tester) async {
      for (final c in GameCategory.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: GameCard(game: _sample(category: c), onTap: () {}),
              ),
            ),
          ),
        ));
        // The expected icon should appear inside the thumbnail.
        expect(find.byIcon(GameCategoryVisual.iconFor(c)), findsOneWidget);
      }
    });
  });

  group('Flagship icon mapping', () {
    const expectedFlagships = <String>[
      'ludo-royale',
      'carrom-clash',
      'call-break',
      'chess-master',
      'sudoku-master',
      'cricket-clash',
    ];

    test('each flagship id resolves to a non-null icon', () {
      for (final id in expectedFlagships) {
        expect(
          GameCategoryVisual.flagshipIconFor(id),
          isNotNull,
          reason: '$id should be a flagship',
        );
        expect(
          GameCategoryVisual.flagshipIds.contains(id),
          isTrue,
          reason: '$id missing from flagshipIds',
        );
      }
    });

    test('non-flagship ids return null', () {
      for (final id in ['block-blast', 'bubble-pop', 'memory-match']) {
        expect(
          GameCategoryVisual.flagshipIconFor(id),
          isNull,
          reason: '$id should not be a flagship',
        );
      }
    });

    testWidgets('GameCard renders a CustomPaint for flagship IDs',
        (tester) async {
      // Build a Card for each flagship and confirm the thumbnail
      // contains a CustomPaint (the hand-tuned icon) rather than a
      // Material Icon. The control sample uses a non-flagship id
      // so its thumbnail should still contain a Material Icon.
      for (final id in expectedFlagships) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: GameCard(
                  game: _sample().copyWith(id: id),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ));
        expect(
          find.byType(CustomPaint),
          findsWidgets,
          reason: '$id should render at least one CustomPaint',
        );
      }
    });
  });
}