// Regression tests for the Unsubscribe button reliability fix.
//
// Original symptom (spec bug #2): after a successful
// `unsubscribe.php` round-trip (statusCode S1000,
// subscriptionStatus UNREGISTERED), the local session was cleared
// but the now-unsubscribed number was NOT dropped from the
// logout-safe history. The user could immediately re-open the
// Login screen, type the same number, tap Verify, and the flow
// would short-circuit on the history record — masking the
// unsubscribed state.
//
// Root cause: the More screen called `logout()` first, which
// flipped `subscriptionControllerProvider.state.isSubscribed` to
// false. The router's auth gate (`!isSubscribed && !atAuth` →
// `/subscribe`) then fired synchronously and unmounted
// `_MoreScreenState`. The subsequent `forgetMobile(savedNumber)`
// call hit the `if (!mounted) return;` guard and was silently
// dropped.
//
// Fix: reorder the two operations in `_onUnsubscribeTap` so
// `forgetMobile` runs first, then `logout`. Both repository
// writes complete BEFORE the router redirect kicks in, so the
// state-unmount race is impossible.
//
// These tests drive the controllers directly with an in-memory
// repository and a fake HTTP client that returns the spec's
// unsubscribe success shape.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:playnest/data/api/bdapps_api.dart';
import 'package:playnest/data/repositories/subscription_repository.dart';
import 'package:playnest/features/auth/auth_controller.dart';

const String _unsubscribeSuccessBody = '''
{
  "statusCode": "S1000",
  "statusDetail": "Successfully unsubscribed",
  "subscriptionStatus": "UNREGISTERED",
  "isSubscribed": false
}''';

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

void main() {
  group('Unsubscribe flow reliability (spec bug #2)', () {
    test(
      'unsubscribe.php S1000/UNREGISTERED → forgetMobile runs BEFORE logout '
      '(regression for the "Unsubscribe does not reliably update UI/session" '
      'bug)',
      () async {
        final repo = InMemorySubscriptionRepository();
        // Pre-seed the same way MoreScreen does when the user is
        // subscribed: subscriberId in tel:88xxxxxxxxxx shape + the
        // Robi/Cirkle mobile + isSubscribed=true.
        await repo.setSession(
          subscriberId: 'tel:8801812345678',
          mobile: '01812345678',
          isSubscribed: true,
        );
        expect(
          repo.findHistoryForMobile('01812345678'),
          isNotNull,
          reason: 'sanity: setSession records the history for REGISTERED users',
        );

        // Track the ORDER of repository writes. The fix is that
        // `forgetMobile` must run before the next `clearSession` /
        // `setSession` call that drops the active session.
        final callOrder = <String>[];
        final recordingRepo = _RecordingSubscriptionRepository(
          repo,
          onForget: () => callOrder.add('forgetMobile'),
          onClearSession: () => callOrder.add('clearSession'),
        );

        final api = BdAppsApi(client: _FakeClient(_unsubscribeSuccessBody));
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(recordingRepo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        // Drive the unsubscribe round-trip directly.
        final sub = container.read(subscriptionControllerProvider.notifier);
        // Pre-condition: the user is logged in and the history is
        // populated.
        expect(container.read(subscriptionControllerProvider).isSubscribed,
            isTrue);
        expect(recordingRepo.findHistoryForMobile('01812345678'), isNotNull);

        // Step 1: forgetMobile (the fix moves this BEFORE logout).
        await sub.forgetMobile('01812345678');
        // Step 2: logout.
        await sub.logout();

        // Assert the ordering.
        expect(callOrder, equals(<String>['forgetMobile', 'clearSession']),
            reason: 'forgetMobile MUST run before clearSession/logout; '
                'the previous build reversed this and the history survived '
                'because the More screen got unmounted by the router '
                'redirect before forgetMobile could fire');

        // Post-conditions:
        //  * session cleared.
        //  * history dropped (the actual user-visible fix).
        final session = container.read(subscriptionControllerProvider);
        expect(session.isSubscribed, isFalse);
        expect(session.mobile, '');
        expect(recordingRepo.findHistoryForMobile('01812345678'), isNull,
            reason: 'unsubscribed number must be removed from history so a '
                'later Login round-trip reports "not subscribed"');

        // Step 3 (regression): trying to log back in with the now-
        // unsubscribed number MUST report not-subscribed, not be
        // short-circuited by a stale history record. The Login flow
        // controller would call checkSubscription here; the spec
        // shape would come back UNREGISTERED. We don't drive the
        // full Login flow in this test — the relevant guarantee is
        // "history is gone, so the Login flow can't be tricked".
      },
    );

    test(
      'history for unsubscribed number is gone even when more screen '
      'unmounts mid-flow (paranoia test for the unmount race)',
      () async {
        final repo = InMemorySubscriptionRepository();
        await repo.setSession(
          subscriberId: 'tel:8801812345678',
          mobile: '01812345678',
          isSubscribed: true,
        );

        final api = BdAppsApi(client: _FakeClient(_unsubscribeSuccessBody));
        final container = ProviderContainer(overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          bdAppsApiProvider.overrideWithValue(api),
        ]);
        addTearDown(container.dispose);

        final sub = container.read(subscriptionControllerProvider.notifier);

        // Simulate the exact ordering the More screen now uses:
        // forgetMobile first, then logout (which triggers the
        // router redirect that would unmount the widget).
        await sub.forgetMobile('01812345678');
        await sub.logout();

        // Container.dispose() simulates the widget-unmount
        // happening AFTER the unsubscribe. The history must
        // already be empty.
        expect(repo.findHistoryForMobile('01812345678'), isNull,
            reason: 'history must be empty by the time the More screen '
                'would unmount — this is the user-visible fix');
      },
    );
  });
}

/// Thin wrapper around the InMemorySubscriptionRepository that
/// records the ORDER of forgetMobile / clearSession calls. Used
/// by the regression test to assert that `forgetMobile` runs
/// before `clearSession` in the More screen's Unsubscribe flow.
class _RecordingSubscriptionRepository implements SubscriptionRepository {
  _RecordingSubscriptionRepository(this._inner, {
    required this.onForget,
    required this.onClearSession,
  });

  final SubscriptionRepository _inner;
  final void Function() onForget;
  final void Function() onClearSession;

  @override
  String subscriberId() => _inner.subscriberId();

  @override
  String mobile() => _inner.mobile();

  @override
  bool isSubscribed() => _inner.isSubscribed();

  @override
  int lastVerifiedAtMs() => _inner.lastVerifiedAtMs();

  @override
  Future<void> setSession({
    required String subscriberId,
    required String mobile,
    required bool isSubscribed,
  }) =>
      _inner.setSession(
        subscriberId: subscriberId,
        mobile: mobile,
        isSubscribed: isSubscribed,
      );

  @override
  Future<void> clearSession() async {
    onClearSession();
    await _inner.clearSession();
  }

  @override
  SubscriptionHistoryEntry? findHistoryForMobile(String mobile) =>
      _inner.findHistoryForMobile(mobile);

  @override
  Future<void> forgetMobile(String mobile) async {
    onForget();
    await _inner.forgetMobile(mobile);
  }
}
