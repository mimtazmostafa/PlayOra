// End-to-end coverage for the spec's "FULL FLOW" checklist (Step 3).
//
// Verdict summary:
//   * Subscribe (in-app OTP) -> logged in  → out of scope here; the
//     OTP path is unchanged from the working build.
//   * Landing-page subscriber -> Login screen with their number ->
//     logged in (same backend, same rule).
//   * Log out -> log back in with same number -> works, any number
//     of times, as long as still subscribed.
//   * App start/resume: silently re-check subscription; if
//     UNREGISTERED, log the user out; if network error, keep them
//     logged in.
//   * Unsubscribe button -> confirms -> calls unsubscribe.php ->
//     clears session -> back to Welcome/Login screen.
//   * Logging in again with that now-unsubscribed number ->
//     correctly shown as not subscribed, no freeze.
//   * Malformed number (wrong length/prefix) -> blocked locally,
//     no network call.
//   * No internet -> clean error + retry, never falsely "not
//     subscribed".
//
// These tests drive the controllers directly with an in-memory
// repository and a programmable HTTP client — that lets us
// simulate the full state machine without spinning up a fake
// router.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:playnest/data/api/bdapps_api.dart';
import 'package:playnest/data/repositories/subscription_repository.dart';
import 'package:playnest/features/auth/auth_controller.dart';
import 'package:playnest/features/auth/auth_flow_controller.dart';

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
  "statusDetail": "User is not subscribed",
  "isSubscribed": false,
  "subscriptionStatus": "UNREGISTERED",
  "subscriberId": "tel:8801812345678"
}''';

const String _unsubscribeOkBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "Successfully unsubscribed",
  "subscriptionStatus": "UNREGISTERED",
  "isSubscribed": false
}''';

/// Programmable HTTP client: feeds the caller a queued response
/// for each send, in order. Lets one test cover the full
/// login→logout→login→unsubscribe round-trip.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this._responses);

  final List<String> _responses;
  int sentCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentCount++;
    final body = _responses.isNotEmpty
        ? _responses.removeAt(0)
        : _notSubscribedBody;
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      contentLength: bytes.length,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('Step 3 — full flow end-to-end', () {
    test(
      'Landing-page subscriber → Login → logged in (REGISTERED verdict)',
      () async {
        final api = BdAppsApi(client: _ScriptedClient([_registeredBody]));
        final repo = InMemorySubscriptionRepository();
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        // Pre-condition: no session.
        expect(container.read(subscriptionControllerProvider).isSubscribed,
            isFalse);

        // User types their number on Login, taps Verify.
        final flow = container.read(loginFlowControllerProvider.notifier)
          ..setMobile('01812345678');
        final ok = await flow.verifyAndContinue();

        expect(ok, isTrue,
            reason: 'REGISTERED verdict must grant access');
        expect(container.read(subscriptionControllerProvider).isSubscribed,
            isTrue);
        expect(container.read(subscriptionControllerProvider).mobile,
            '01812345678');
        expect(
          container.read(subscriptionControllerProvider).subscriberId,
          'tel:8801812345678',
        );
      },
    );

    test(
      'Logout → log back in with same number → works (any number of times, '
      'while still subscribed)',
      () async {
        // Two round-trips per iteration (verify + re-verify) ×
        // 5 iterations = 10 REGISTERED answers.
        final api = BdAppsApi(
            client: _ScriptedClient(
                List<String>.filled(10, _registeredBody,
                    growable: true)));
        final repo = InMemorySubscriptionRepository();
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        final sub = container.read(subscriptionControllerProvider.notifier);
        final flow = container.read(loginFlowControllerProvider.notifier);

        for (var i = 0; i < 5; i++) {
          // First login from the landing page.
          flow.setMobile('01812345678');
          final ok1 = await flow.verifyAndContinue();
          expect(ok1, isTrue, reason: 'login #$i must succeed');

          // Logout from the More tab.
          await sub.logout();
          expect(container.read(subscriptionControllerProvider).isSubscribed,
              isFalse,
              reason: 'logout #$i must clear the session');

          // Re-login with the same number.
          flow.setMobile('01812345678');
          final ok2 = await flow.verifyAndContinue();
          expect(ok2, isTrue,
              reason: 're-login #$i must succeed while still REGISTERED '
                  'upstream');
          expect(container.read(subscriptionControllerProvider).isSubscribed,
              isTrue);
        }
      },
    );

    test(
      'App start/resume background verify: UNREGISTERED → clears session; '
      'network error → keeps logged in',
      () async {
        // Case 1: upstream says UNREGISTERED → silent clear.
        {
          final api = BdAppsApi(client: _ScriptedClient([_notSubscribedBody]));
          final repo = InMemorySubscriptionRepository();
          await repo.setSession(
            subscriberId: 'tel:8801812345678',
            mobile: '01812345678',
            isSubscribed: true,
          );
          final container = ProviderContainer(overrides: [
            subscriptionRepositoryProvider.overrideWithValue(repo),
            bdAppsApiProvider.overrideWithValue(api),
          ]);
          addTearDown(container.dispose);

          // Sanity: the session is alive before the background verify.
          expect(container.read(subscriptionControllerProvider).isSubscribed,
              isTrue);

          // The controller debounces on lastVerifiedAtMs (1h
          // default). Advance the clock past the debounce window
          // so the verify actually fires.
          final futureNow =
              DateTime.now().add(const Duration(hours: 2));
          await container
              .read(subscriptionControllerProvider.notifier)
              .verifySessionInBackground(now: futureNow);

          expect(container.read(subscriptionControllerProvider).isSubscribed,
              isFalse,
              reason: 'background verify that returns UNREGISTERED must '
                  'silently log the user out');
        }

        // Case 2: network error → keeps the session.
        {
          final api = BdAppsApi(client: _AlwaysThrowClient());
          final repo = InMemorySubscriptionRepository();
          await repo.setSession(
            subscriberId: 'tel:8801812345678',
            mobile: '01812345678',
            isSubscribed: true,
          );
          final container = ProviderContainer(overrides: [
            subscriptionRepositoryProvider.overrideWithValue(repo),
            bdAppsApiProvider.overrideWithValue(api),
          ]);
          addTearDown(container.dispose);

          await container
              .read(subscriptionControllerProvider.notifier)
              .verifySessionInBackground(
                now: DateTime.now().add(const Duration(hours: 2)),
              );

          expect(container.read(subscriptionControllerProvider).isSubscribed,
              isTrue,
              reason: 'background verify that hits a network error must '
                  'keep the user logged in — a transient blip must not '
                  'kick a paid-up user out');
        }
      },
    );

    test(
      'Unsubscribe button → S1000/UNREGISTERED → session cleared + history '
      'dropped → subsequent login reports not-subscribed',
      () async {
        // The scripted client serves:
        //   1. unsubscribe.php → S1000 UNREGISTERED
        //   2. check_subscription.php → S1000 UNREGISTERED (re-login probe)
        final api = BdAppsApi(
          client: _ScriptedClient([_unsubscribeOkBody, _notSubscribedBody]),
        );
        final repo = InMemorySubscriptionRepository();
        await repo.setSession(
          subscriberId: 'tel:8801812345678',
          mobile: '01812345678',
          isSubscribed: true,
        );

        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        final sub = container.read(subscriptionControllerProvider.notifier);
        final flow = container.read(loginFlowControllerProvider.notifier);

        // ── Step A: tap Unsubscribe → spec-shaped success ──
        final result =
            await api.unsubscribe(mobile: '01812345678');
        expect(result.isNotSubscribed, isTrue,
            reason: 'S1000 + UNREGISTERED must map to notSubscribed so '
                'the More screen treats it as a clean success');

        // Apply the same ordering the More screen now uses.
        await sub.forgetMobile('01812345678');
        await sub.logout();

        expect(container.read(subscriptionControllerProvider).isSubscribed,
            isFalse);
        expect(repo.findHistoryForMobile('01812345678'), isNull,
            reason: 'history must be dropped so the Login flow cannot '
                'mask the unsubscribed state');

        // ── Step B: log back in with the same (now-unsubscribed) number ──
        flow.setMobile('01812345678');
        final ok = await flow.verifyAndContinue();
        expect(ok, isFalse,
            reason: 'login with an unsubscribed number must return false');
        expect(container.read(loginFlowControllerProvider).verdict,
            LoginVerdict.notSubscribed,
            reason: 'verdict must be notSubscribed so the panel renders '
                'the Subscribe CTA — must NOT silently grant access');
      },
    );

    test(
      'Malformed number → blocked locally, no network call',
      () async {
        final client = _ScriptedClient(<String>[]);
        final api = BdAppsApi(client: client);
        final repo = InMemorySubscriptionRepository();
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        final flow = container.read(loginFlowControllerProvider.notifier);

        // Empty input.
        flow.setMobile('');
        final okEmpty = await flow.verifyAndContinue();
        expect(okEmpty, isFalse);
        expect(client.sentCount, 0,
            reason: 'empty number must be rejected locally');

        // Wrong length.
        flow.setMobile('0181234'); // only 7 digits
        final okShort = await flow.verifyAndContinue();
        expect(okShort, isFalse);
        expect(client.sentCount, 0,
            reason: 'too-short number must be rejected locally');

        // Wrong carrier prefix (Grameenphone 017).
        flow.setMobile('01712345678');
        final okWrongPrefix = await flow.verifyAndContinue();
        expect(okWrongPrefix, isFalse);
        expect(client.sentCount, 0,
            reason: '017 number must be rejected locally — only Robi '
                '(018) and Cirkle (016) are accepted by bdapps');
      },
    );

    test(
      'No internet → clean error + retry, never falsely "not subscribed"',
      () async {
        final api = BdAppsApi(client: _AlwaysThrowClient());
        final repo = InMemorySubscriptionRepository();
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        final flow = container.read(loginFlowControllerProvider.notifier)
          ..setMobile('01812345678');
        final ok = await flow.verifyAndContinue();

        expect(ok, isFalse);
        expect(container.read(loginFlowControllerProvider).verdict,
            LoginVerdict.retryable,
            reason: 'transport failure must surface as retryable — NEVER '
                'as notSubscribed');
        expect(container.read(loginFlowControllerProvider).errorMessage,
            contains('try again'),
            reason: 'clean error copy must mention retry');
      },
    );

    test(
      'Network failure during background verify keeps the session intact '
      '(regression for "no internet → falsely logged out")',
      () async {
        final api = BdAppsApi(client: _AlwaysThrowClient());
        final repo = InMemorySubscriptionRepository();
        await repo.setSession(
          subscriberId: 'tel:8801812345678',
          mobile: '01812345678',
          isSubscribed: true,
        );
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        await container
            .read(subscriptionControllerProvider.notifier)
            .verifySessionInBackground(
              now: DateTime.now().add(const Duration(hours: 2)),
            );

        final session = container.read(subscriptionControllerProvider);
        expect(session.isSubscribed, isTrue,
            reason: 'offline cold-start must NOT log the user out — '
                'a transient blip must not bounce a paid-up user');
        expect(session.mobile, '01812345678',
            reason: 'the saved session is preserved verbatim');
      },
    );
  });
}

class _AlwaysThrowClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw Exception('simulated no-internet');
  }
}
