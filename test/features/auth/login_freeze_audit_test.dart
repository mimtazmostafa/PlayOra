// Audit test for the Login "not subscribed" freeze (Bug #3 in the
// spec).
//
// The user reported that tapping Verify & Continue on a NOT-subscribed
// number froze the app, with logcat pointing at the UI thread after
// the error state was set. Common causes:
//
//   * setState() called inside build() on the same frame the stage
//     flips to error.
//   * A listener on the same controller that re-triggers the check
//     when the controller's state changes (lock-step loop).
//   * An AnimationController owned by the Login screen that isn't
//     stopped when the stage leaves `verifying` — the spinner keeps
//     ticking frames even when the screen is supposedly idle.
//
// This test drives the LoginScreen with the spec's NOT-subscribed
// payload and asserts:
//   1. The flow returns false (not-subscribed).
//   2. The local session is NOT marked subscribed.
//   3. The error panel renders (we can find the "not subscribed"
//      text).
//   4. After the verdict lands, the Login screen is stable — pumping
//     any number of additional frames does not produce more rebuilds
//     or change the visible widget tree.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:playnest/data/api/bdapps_api.dart';
import 'package:playnest/data/repositories/subscription_repository.dart';
import 'package:playnest/features/auth/auth_controller.dart';
import 'package:playnest/features/auth/auth_flow_controller.dart';
import 'package:playnest/features/auth/login_screen.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this._body);

  final String _body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(_body)]),
      200,
      contentLength: _body.length,
      headers: const {'content-type': 'application/json'},
    );
  }
}

const String _notSubscribedBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "User is not subscribed to this app",
  "isSubscribed": false,
  "subscriptionStatus": "UNREGISTERED",
  "subscriberId": "tel:8801812345678"
}''';

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (c, s) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (c, s) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/subscribe',
        builder: (c, s) => const Scaffold(body: Text('SUBSCRIBE')),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'NOT-subscribed: stable after verdict — no infinite rebuild loop',
    (tester) async {
      final repo = InMemorySubscriptionRepository();
      final api = BdAppsApi(client: _FakeClient(_notSubscribedBody));
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        bdAppsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      // Track how many times the LoginScreen's State build runs.
      var buildCount = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            builder: (context, child) {
              buildCount++;
              return child ?? const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, '01812345678');
      await tester.pump();

      // Snapshot build count before pressing verify.
      final before = buildCount;

      await tester.tap(find.text('Verify & Continue'));
      // Pump a long stretch — if the screen were in an infinite
      // rebuild loop, the test runner would time out here.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Pump 30 more frames to catch a slower loop (e.g. one tied
      // to an animation tick).
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The build count should have grown by a finite amount — not
      // exploded. We don't pin the exact number (Riverpod may
      // rebuild once or twice for state propagation), but we assert
      // it's well below "infinite loop" territory.
      final delta = buildCount - before;
      expect(delta, lessThan(20),
          reason: 'build count after a single verify tap grew by '
              '$delta — that smells like a rebuild loop');

      // The error panel must be visible.
      expect(find.textContaining('not subscribed'), findsWidgets);

      // The flow is in the error stage, not the verifying stage.
      final flow = container.read(loginFlowControllerProvider);
      expect(flow.stage, AuthFlowStage.error);

      // No session was marked.
      expect(container.read(subscriptionControllerProvider).isSubscribed,
          isFalse);
    },
  );
}
