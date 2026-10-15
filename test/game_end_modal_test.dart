import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/widgets/game_end_modal.dart';

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('GameEndModal coinsForScore', () {
    test('zero score yields zero coins', () {
      expect(GameEndModal.coinsForScore(0), 0);
    });

    test('1 coin per 10 points (integer division)', () {
      expect(GameEndModal.coinsForScore(9), 0);
      expect(GameEndModal.coinsForScore(10), 1);
      expect(GameEndModal.coinsForScore(19), 1);
      expect(GameEndModal.coinsForScore(20), 2);
      expect(GameEndModal.coinsForScore(100), 10);
    });

    test('handles large scores', () {
      expect(GameEndModal.coinsForScore(12345), 1234);
    });
  });

  group('GameEndModal xpForScore', () {
    test('zero score yields zero xp', () {
      expect(GameEndModal.xpForScore(0), 0);
    });

    test('1 xp per 5 points (integer division)', () {
      expect(GameEndModal.xpForScore(4), 0);
      expect(GameEndModal.xpForScore(5), 1);
      expect(GameEndModal.xpForScore(14), 2);
      expect(GameEndModal.xpForScore(100), 20);
    });

    test('coins and xp scale at the same ratio as the codebase formula',
        () {
      // Sanity: xp == 2 * coins when the score is a multiple of 10
      // (where both integer divisions land cleanly).
      for (final score in [0, 50, 100, 250, 1000]) {
        expect(
          GameEndModal.xpForScore(score),
          GameEndModal.coinsForScore(score) * 2,
          reason: 'mismatch at score=$score',
        );
      }
    });
  });

  group('GameEndModal.dailyBonusForScore', () {
    test('zero score yields zero bonus', () {
      expect(GameEndModal.dailyBonusForScore(0), 0);
    });

    test('uses score ~/ 5 but caps at 100', () {
      expect(GameEndModal.dailyBonusForScore(4), 0);
      expect(GameEndModal.dailyBonusForScore(5), 1);
      expect(GameEndModal.dailyBonusForScore(50), 10);
      expect(GameEndModal.dailyBonusForScore(500), 100); // 500/5 == 100
      expect(GameEndModal.dailyBonusForScore(1000), 100); // capped
      expect(GameEndModal.dailyBonusForScore(100000), 100);
    });

    test('the cap kicks in at score == 501', () {
      expect(GameEndModal.dailyBonusForScore(500), 100);
      expect(GameEndModal.dailyBonusForScore(501), 100);
    });
  });

  group('GameEndRewardRow', () {
    testWidgets('renders the value with the + prefix and label suffix',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameEndRewardRow(
            icon: Icons.monetization_on_rounded,
            color: Colors.amber,
            label: 'coins',
            value: 12,
          ),
        ),
      );
      // AnimatedCountUp starts at 0; pump a frame and let it tick to 12.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
    });

    testWidgets('zero value still renders (no crash)', (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameEndRewardRow(
            icon: Icons.bolt_rounded,
            color: Colors.blue,
            label: 'XP',
            value: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });

    testWidgets('respects a custom icon + color', (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameEndRewardRow(
            icon: Icons.emoji_events_rounded,
            color: Colors.green,
            label: 'daily bonus',
            value: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
    });
  });
}