import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playnest/features/game_player/widgets/game_pause_overlay.dart';

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('GamePauseOverlay', () {
    testWidgets('renders the title and copy', (tester) async {
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () {},
            onQuitToDetails: () {},
            onQuitToHome: () {},
          ),
        ),
      );
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.text('Take a break. Your progress is safe.'),
        findsOneWidget,
      );
    });

    testWidgets('renders the three action buttons', (tester) async {
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () {},
            onQuitToDetails: () {},
            onQuitToHome: () {},
          ),
        ),
      );
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Quit to Details'), findsOneWidget);
      expect(find.text('Quit to Home'), findsOneWidget);
    });

    testWidgets('Resume button invokes onResume', (tester) async {
      var resumeCount = 0;
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () => resumeCount++,
            onQuitToDetails: () {},
            onQuitToHome: () {},
          ),
        ),
      );
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(resumeCount, 1);
    });

    testWidgets('Quit to Details button invokes onQuitToDetails',
        (tester) async {
      var detailsCount = 0;
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () {},
            onQuitToDetails: () => detailsCount++,
            onQuitToHome: () {},
          ),
        ),
      );
      await tester.tap(find.text('Quit to Details'));
      await tester.pump();
      expect(detailsCount, 1);
    });

    testWidgets('Quit to Home button invokes onQuitToHome',
        (tester) async {
      var homeCount = 0;
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () {},
            onQuitToDetails: () {},
            onQuitToHome: () => homeCount++,
          ),
        ),
      );
      await tester.tap(find.text('Quit to Home'));
      await tester.pump();
      expect(homeCount, 1);
    });

    testWidgets('renders the pause icon', (tester) async {
      await tester.pumpWidget(
        _harness(
          GamePauseOverlay(
            onResume: () {},
            onQuitToDetails: () {},
            onQuitToHome: () {},
          ),
        ),
      );
      expect(
        find.byIcon(Icons.pause_circle_filled_rounded),
        findsOneWidget,
      );
    });
  });

  group('GamePauseOverlay.show', () {
    testWidgets('opens via showGeneralDialog and dismisses on Resume',
        (tester) async {
      var resumeCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => GamePauseOverlay.show(
                    context,
                    onResume: () async => resumeCount++,
                    onQuitToDetails: () async {},
                    onQuitToHome: () async {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsNothing);
      expect(resumeCount, 1);
    });
  });
}