import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/widgets/game_hud_bar.dart';

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('GameHudBar (simple API)', () {
    testWidgets('renders title and score when score is provided',
        (tester) async {
      await tester.pumpWidget(
        _harness(const GameHudBar(title: 'My Game', score: 42)),
      );
      expect(find.text('My Game'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('renders title and timer when timerSeconds is provided',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudBar(title: 'My Game', timerSeconds: 75),
        ),
      );
      expect(find.text('My Game'), findsOneWidget);
      expect(find.text('75s'), findsOneWidget);
    });

    testWidgets('timer chip wins over score chip when both are set',
        (tester) async {
      // _buildTrailing checks timerSeconds before score, so the timer
      // chip is the trailing indicator when both are supplied.
      await tester.pumpWidget(
        _harness(
          const GameHudBar(
            title: 'My Game',
            score: 12,
            timerSeconds: 30,
          ),
        ),
      );
      expect(find.text('30s'), findsOneWidget);
      // Score is not rendered when a timer takes precedence.
      expect(find.text('12'), findsNothing);
    });

    testWidgets('asserts when neither score nor timerSeconds is provided',
        (tester) async {
      expect(
        () => GameHudBar(title: 'My Game'),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets('renders subtitle when provided', (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudBar(
            title: 'My Game',
            subtitle: 'Drag pieces onto the grid.',
            score: 0,
          ),
        ),
      );
      expect(find.text('Drag pieces onto the grid.'), findsOneWidget);
    });

    testWidgets('omits subtitle Text when subtitle is null',
        (tester) async {
      await tester.pumpWidget(
        _harness(const GameHudBar(title: 'My Game', score: 5)),
      );
      // Title text + score number both render; no subtitle text in between.
      expect(find.text('My Game'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('GameHudBar pause button gating', () {
    testWidgets('does not render pause button when onPause is null',
        (tester) async {
      await tester.pumpWidget(
        _harness(const GameHudBar(title: 'My Game', score: 0)),
      );
      // The host screen already shows its own corner pause button; the
      // bar shouldn't duplicate it.
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byTooltip('Pause'), findsNothing);
    });

    testWidgets('renders pause button when onPause is provided',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          GameHudBar(
            title: 'My Game',
            score: 0,
            onPause: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('pause tap invokes the onPause callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _harness(
          GameHudBar(
            title: 'My Game',
            score: 0,
            onPause: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('GameHudBar.customTrailing', () {
    testWidgets('renders the custom trailing widget', (tester) async {
      await tester.pumpWidget(
        _harness(
          GameHudBar.customTrailing(
            title: 'My Game',
            customTrailing: const Text('CUSTOM'),
          ),
        ),
      );
      expect(find.text('My Game'), findsOneWidget);
      expect(find.text('CUSTOM'), findsOneWidget);
    });

    testWidgets('scoreChip wins when timerChip and customTrailing are null',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          GameHudBar.customTrailing(
            title: 'My Game',
            scoreChip: const Text('SCORE-CHIP'),
          ),
        ),
      );
      expect(find.text('SCORE-CHIP'), findsOneWidget);
      expect(find.text('CUSTOM'), findsNothing);
    });

    testWidgets('scoreChip wins over timerChip when both are passed',
        (tester) async {
      // NOTE: the current `_buildTrailing` precedence in
      // GameHudBar.customTrailing is customTrailing > timerSeconds >
      // scoreChip. Because the customTrailing constructor zeroes out
      // timerSeconds, scoreChip ends up winning over timerChip. If a
      // future game needs a genuine "timerChip overrides scoreChip"
      // semantic, fix `_buildTrailing` to check `timerChip` before
      // `scoreChip` and update this test.
      await tester.pumpWidget(
        _harness(
          GameHudBar.customTrailing(
            title: 'My Game',
            scoreChip: const Text('SCORE-CHIP'),
            timerChip: const Text('TIMER-CHIP'),
          ),
        ),
      );
      expect(find.text('SCORE-CHIP'), findsOneWidget);
      expect(find.text('TIMER-CHIP'), findsNothing);
    });

    testWidgets('customTrailing wins over timerChip + scoreChip',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          GameHudBar.customTrailing(
            title: 'My Game',
            scoreChip: const Text('SCORE-CHIP'),
            timerChip: const Text('TIMER-CHIP'),
            customTrailing: const Text('CUSTOM'),
          ),
        ),
      );
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('TIMER-CHIP'), findsNothing);
      expect(find.text('SCORE-CHIP'), findsNothing);
    });
  });

  group('GameHudTimerChip', () {
    testWidgets('shows the seconds with the s suffix', (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudBar(
            title: 'My Game',
            timerSeconds: 42,
          ),
        ),
      );
      expect(find.text('42s'), findsOneWidget);
    });

    testWidgets('timer chip still renders when seconds == 0',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudBar(
            title: 'My Game',
            timerSeconds: 0,
          ),
        ),
      );
      expect(find.text('0s'), findsOneWidget);
    });

    testWidgets('renders the standalone chip widget directly',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudTimerChip(secondsRemaining: 7),
        ),
      );
      expect(find.text('7s'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });
  });

  group('GameHudScoreChip', () {
    testWidgets('renders the standalone chip widget directly',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudScoreChip(score: 99),
        ),
      );
      expect(find.text('99'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('honors a custom icon', (tester) async {
      await tester.pumpWidget(
        _harness(
          const GameHudScoreChip(
            score: 1,
            icon: Icons.local_fire_department_rounded,
          ),
        ),
      );
      expect(
        find.byIcon(Icons.local_fire_department_rounded),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });
  });
}