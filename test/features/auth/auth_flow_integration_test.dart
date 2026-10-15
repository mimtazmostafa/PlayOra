// End-to-end style tests for the Login + Unsubscribe flows.
//
// Drive the actual LoginScreen widget through `tester.pumpWidget` with
// a fake HTTP client, then assert what the user observes.

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

const String _registeredBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "User is subscribed",
  "isSubscribed": true,
  "subscriptionStatus": "REGISTERED",
  "subscriberId": "tel:8801812345678"
}''';

const String _notSubscribedBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "User is not subscribed to this app",
  "isSubscribed": false,
  "subscriptionStatus": "UNREGISTERED",
  "subscriberId": "tel:8801812345678"
}''';

GoRouter _buildLoginRouter() {
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

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: _buildLoginRouter()),
  );
}

void main() {
  testWidgets(
    'Login: REGISTERED number — user is marked subscribed (no freeze, no loop)',
    (tester) async {
      final repo = InMemorySubscriptionRepository();
      final api = BdAppsApi(client: _FakeClient(_registeredBody));
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        bdAppsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      // Type the registered mobile into the Login field.
      await tester.enterText(
          find.byType(TextField).first, '01812345678');
      await tester.pump();

      // Tap "Verify & Continue".
      await tester.tap(find.text('Verify & Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();

      final session = container.read(subscriptionControllerProvider);
      expect(session.isSubscribed, isTrue,
          reason: 'REGISTERED verdict must mark the session locally');
      expect(session.mobile, '01812345678');

      // Frame pump after success must not hang the test runner.
      await tester.pump(const Duration(milliseconds: 16));
    },
  );

  testWidgets(
    'Login: NOT-subscribed number — error panel shows, no freeze',
    (tester) async {
      final repo = InMemorySubscriptionRepository();
      final api = BdAppsApi(client: _FakeClient(_notSubscribedBody));
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        bdAppsApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, '01812345678');
      await tester.pump();
      await tester.tap(find.text('Verify & Continue'));
      await tester.pumpAndSettle();

      final session = container.read(subscriptionControllerProvider);
      expect(session.isSubscribed, isFalse);

      // The Login screen must show the "not subscribed" panel
      // (the panel includes the message + a Subscribe CTA).
      expect(find.textContaining('not subscribed'), findsWidgets);

      // Frame pump after error must not hang the test runner.
      await tester.pump(const Duration(milliseconds: 16));
    },
  );

  testWidgets(
    'BdAppsCheckResult.verdict — REGISTERED round-trip parses correctly',
    (tester) async {
      final api = BdAppsApi(client: _FakeClient(_registeredBody));
      final result = await api.checkSubscription(mobile: '01812345678');
      expect(result.isSubscribed, isTrue);
      expect(result.isNotSubscribed, isFalse);
      expect(result.isError, isFalse);
    },
  );
}
