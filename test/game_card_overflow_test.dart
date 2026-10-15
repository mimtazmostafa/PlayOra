import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/data/models/game_category.dart';
import 'package:playnest/data/models/game_difficulty.dart';
import 'package:playnest/data/models/game_model.dart';
import 'package:playnest/data/models/game_type.dart';
import 'package:playnest/features/games/widgets/game_card.dart';

/// Regression test for the "BOTTOM OVERFLOWED BY X PIXELS" bug seen on
/// every game card across Categories and Home screens.
///
/// The fix has three parts that the test exercises together:
///
/// 1. `GameCard` wraps its text rows in `Flexible`, so a long Bangla
///    title or English title can never push the card past its tile
///    height.
/// 2. `title` / `titleBangla` both use `maxLines: 1` +
///    `TextOverflow.ellipsis` so they truncate cleanly instead of
///    wrapping.
/// 3. The thumbnail's `AspectRatio(4/3)` (instead of `1`) leaves
///    enough vertical room for the three text rows even at the
///    smallest `childAspectRatio` the grid uses.
///
/// We render the longest catalog entry — "Ludo Royale" / "লুডো রয়েল" /
/// 25 min — at the exact tile size the grid uses
/// (`childAspectRatio: 0.72`, two-column grid at 360dp wide with
/// `AppSpacing.lg` insets/spacing) and assert the rendered card
/// height is within the tile height and that no widget reports an
/// overflow.
void main() {
  testWidgets(
    'GameCard does not overflow at the smallest grid tile size for '
    'the longest catalog entry',
    (tester) async {
      // Match the production grid: 2 cols at a 360dp viewport with
      // AppSpacing.lg (24) outer padding and (24) inter-tile spacing.
      // Tile width = (360 - 24*2 - 24) / 2 = 144dp.
      // Tile height = 144 / 0.72 = 200dp.
      const double screenWidth = 360;
      const double tileWidth = (screenWidth - 24 * 2 - 24) / 2; // 144
      const double tileHeight = tileWidth / 0.72; // 200

      const ludoRoyale = Game(
        id: 'ludo-royale',
        title: 'Ludo Royale',
        titleBangla: 'লুডো রয়েল',
        category: GameCategory.board,
        thumbnailAsset: 'assets/thumbs/ludo.png',
        description: 'Classic four-player Ludo.',
        difficulty: GameDifficulty.easy,
        avgSessionMinutes: 25, // longest duration in the catalog
        isOfflineAvailable: true,
        isFavorite: false,
        gameType: GameType.nativeFlutter,
        entryPoint: '/game/ludo-royale',
      );

      await tester.binding.setSurfaceSize(const Size(screenWidth, 800));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: GameCard(
                  game: ludoRoyale,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // 1. The card actually rendered.
      final cardFinder = find.byType(GameCard);
      expect(cardFinder, findsOneWidget);

      // 2. Title and Bangla subtitle both truncate to a single line.
      final titleFinder = find.text('Ludo Royale');
      final subtitleFinder = find.text('লুডো রয়েল');
      expect(titleFinder, findsOneWidget);
      expect(subtitleFinder, findsOneWidget);
      for (final finder in [titleFinder, subtitleFinder]) {
        final widget = tester.widget<Text>(finder);
        expect(widget.maxLines, 1);
        expect(widget.overflow, TextOverflow.ellipsis);
      }

      // 3. The duration pill renders.
      expect(find.text('25 min'), findsOneWidget);

      // 4. Card height stays within the tile height. We assert via
      //    the rendered RenderBox rather than catching a
      //    `FlutterError` because the overflow message depends on
      //    whether the parent grid surfaces it.
      final cardBox = tester.getRect(cardFinder);
      expect(
        cardBox.height,
        lessThanOrEqualTo(tileHeight + 1), // 1px slop for rounding
        reason:
            'GameCard height (${cardBox.height}) must not exceed tile '
            'height ($tileHeight)',
      );

      // 5. No widget under the card tree reports an overflow.
      //    `tester.takeException` captures FlutterError exceptions
      //    that were thrown during layout/paint but not rethrown.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GameCard layout has Flexible so text rows shrink before overflowing',
    (tester) async {
      // Use a pathologically long Bangla title that even an
      // ellipsized single line can't shrink, and verify the card
      // still fits.
      const insane = Game(
        id: 'insane',
        title: 'A very very very very very very very long title',
        titleBangla:
            'লুডো রয়েল লুডো রয়েল লুডো রয়েল লুডো রয়েল লুডো রয়েল '
            'লুডো রয়েল লুডো রয়েল লুডো রয়েল লুডো রয়েল লুডো রয়েল',
        category: GameCategory.board,
        thumbnailAsset: 'assets/thumbs/ludo.png',
        description: '',
        difficulty: GameDifficulty.easy,
        avgSessionMinutes: 25,
        isOfflineAvailable: true,
        isFavorite: false,
        gameType: GameType.nativeFlutter,
        entryPoint: '/x',
      );

      const tileWidth = 144.0;
      const tileHeight = 200.0;

      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: GameCard(game: insane, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final cardBox = tester.getRect(find.byType(GameCard));
      expect(cardBox.height, lessThanOrEqualTo(tileHeight + 1));
    },
  );
}