// Regression tests for the "Verify & Continue" hardening
// (spec bug #3).
//
// Three guarantees the user pinned down explicitly:
//
//   1. The button disables itself while loading — no double-tap
//      can fire a second verify while the first is in flight.
//   2. The controller ignores repeat taps via a re-entrancy
//      guard, so a stale widget tree (queued tap before the
//      rebuild lands) can't sneak a second verify through.
//   3. The loading state is ALWAYS cleared in a `finally` block,
//      so a thrown future (Hive closed mid-write, network hang,
//      upstream parse error) cannot leave the button stuck in
//      its spinner state.

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

const String _registeredBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "User is subscribed",
  "isSubscribed": true,
  "subscriptionStatus": "REGISTERED",
  "subscriberId": "tel:8801812345678"
}''';

/// Fake HTTP client that blocks until a completer is signalled,
/// so we can race a double-tap against an in-flight request.
class _GateableClient extends http.BaseClient {
  _GateableClient(this._body);
  final String _body;
  final Completer<void> _gate = Completer<void>();
  int sentCount = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentCount++;
    await _gate.future;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(_body)]),
      200,
      contentLength: _body.length,
      headers: const {'content-type': 'application/json'},
    );
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (c, s) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
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
    'Verify & Continue — double-tap fires exactly one API call '
    '(button disabled + controller guard)',
    (tester) async {
      final client = _GateableClient(_registeredBody);
      final api = BdAppsApi(client: client);
      final repo = InMemorySubscriptionRepository();
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        bdAppsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: _buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, '01812345678');
      await tester.pump();

      // Tap the button to fire the (gated) request. The button
      // text "Verify & Continue" is replaced by a spinner while
      // the request is in flight, so subsequent taps must look up
      // by widget type rather than by text.
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      // While the spinner is showing, ElevatedButton.onPressed is
      // null (button is disabled). tester.tap on a disabled
      // ElevatedButton is a no-op — exactly the behaviour we want.
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Give the awaiting future one tick so the client has had a
      // chance to register the send.
      await tester.pump(const Duration(milliseconds: 50));

      expect(client.sentCount, 1,
          reason: 'double/triple-tap must collapse to exactly one HTTP call '
              '(button disabled via flow.isBusy + controller _isLoading)');

      // Release the gated response and let the verify complete.
      client.release();
      await tester.pumpAndSettle();

      expect(container.read(subscriptionControllerProvider).isSubscribed,
          isTrue);
    },
  );

  testWidgets(
    'Verify & Continue — thrown future inside verifyAndContinue leaves the '
    'gate clean (finally block clears _isLoading)',
    (tester) async {
      // HTTP client that throws unconditionally. The controller's
      // try/catch should convert the throw into a `retryable`
      // verdict and the `finally` must reset `_isLoading` so the
      // button re-enables.
      final api = BdAppsApi(client: _AlwaysThrowClient());
      final repo = InMemorySubscriptionRepository();
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        bdAppsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: _buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, '01812345678');
      await tester.pump();

      await tester.tap(find.text('Verify & Continue'));
      await tester.pumpAndSettle();

      // After the throw settles, flow should be back to a
      // non-busy stage (error). The Verify & Continue button must
      // be tappable again.
      final flow = container.read(loginFlowControllerProvider);
      expect(flow.isBusy, isFalse,
          reason: 'finally block must reset the busy state even when '
              'the verify path throws');
      expect(flow.stage, AuthFlowStage.error);
      expect(flow.verdict, LoginVerdict.retryable);

      // Tap a second time — the re-entrancy guard must have been
      // cleared, so this either fires a second request (which
      // throws again) or at minimum doesn't deadlock.
      await tester.tap(find.text('Verify & Continue'));
      await tester.pumpAndSettle();

      final flowAfter = container.read(loginFlowControllerProvider);
      expect(flowAfter.isBusy, isFalse);
    },
  );
}

class _AlwaysThrowClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('simulated transport failure');
  }
}
