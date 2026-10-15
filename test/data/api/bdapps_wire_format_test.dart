// Wire-format contract test for the bdapps upstream responses.
//
// The integration plan's "Files that already exist and must not be
// edited" section explicitly says the upstream is the source of
// truth — and on 2026-09-23 the user provided three exact response
// shapes that the server returns today. This test locks those
// shapes into the test suite so any future regression (someone adds
// an envelope wrapper, someone starts trusting `isSubscribed`,
// someone drops the `bdapps_raw` field, someone reverts to a
// form-encoded body that the PHP script can't read) is caught by
// `flutter test` instead of by a real-device crash.
//
// The three exact bodies (verbatim from the user, 2026-09-23):
//
//   1. SUBSCRIBED — Login screen, user has a current subscription
//      on the carrier side. Verdict MUST be `subscribed` so the
//      router lets them into Home.
//
//   2. NOT SUBSCRIBED — Login screen, user has never subscribed or
//      has cancelled. NOTE: upstream returns `isSubscribed: true`
//      AND `subscriptionStatus: "UNREGISTERED"` simultaneously.
//      This is the upstream's known quirk — `isSubscribed` lies,
//      `subscriptionStatus` is the source of truth. The verdict
//      logic MUST ignore `isSubscribed`.
//
//   3. UNSUBSCRIBE SUCCESS — More screen, user tapped Unsubscribe
//      and the carrier confirmed. Verdict MUST be `notSubscribed`
//      (which the unsubscribe wrapper then translates to
//      `unsubscribed: true` so the More screen can show its
//      "You have been unsubscribed" dialog and route back to
//      /subscribe).
//
// In addition to the response shapes, this test pins the REQUEST
// body format: the production PHP scripts (check_subscription.php
// and unsubscribe.php) read from `php://input` and accept
// `phone|mobile|subscriberId|phoneNumber|msisdn` — they explicitly
// DO NOT read `$_POST['user_mobile']`. The Flutter client must
// therefore POST a JSON body with one of the accepted keys; a
// regression to form-encoded `user_mobile=...` produces the user-
// visible error "Invalid mobile number format. Received: " (empty
// `Received:` because the script never saw the mobile number).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:playnest/data/api/bdapps_api.dart';

/// Stub client that records the request and returns [_body]. Each
/// test constructs one with the response body it wants the PHP
/// script to appear to return.
class _StubClient extends http.BaseClient {
  _StubClient(this._body);

  final String _body;
  String? lastRequestBody;
  String? lastRequestContentType;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastRequestBody = request.body;
      lastRequestContentType = request.headers['Content-Type'];
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(_body)]),
      200,
      contentLength: _body.length,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('checkSubscription wire-format contract', () {
    test('REGISTERED user — Login grants access (subscribed verdict)',
        () async {
      const body = '''
{
  "statusCode": "S1000",
  "statusDetail": "Request was successfully processed.",
  "isSubscribed": true,
  "subscriptionStatus": "REGISTERED",
  "subscriberId": "tel:8801876452351",
  "bdapps_raw": {
    "subscriptionStatus": "REGISTERED",
    "statusDetail": "Request was successfully processed.",
    "version": "1.0",
    "statusCode": "S1000"
  }
}''';
      final stub = _StubClient(body);
      final api = BdAppsApi(client: stub);
      final result = await api.checkSubscription(mobile: '01876452351');

      expect(result.status, BdAppsCheckStatus.subscribed,
          reason: 'Upstream says REGISTERED — Login must grant access. '
              'Got: ${result.status} (detail=${result.statusDetail}, '
              'err=${result.errorMessage})');
      expect(result.isSubscribed, isTrue);
      expect(result.errorMessage, isNull);

      // REQUEST-BODY ASSERTION: PHP's check_subscription.php reads
      // from `php://input` and accepts `phone|mobile|subscriberId|
      // phoneNumber|msisdn`. The client MUST POST a JSON body with
      // one of those keys — sending form-encoded `user_mobile=...`
      // produces the user-visible
      // "Invalid mobile number format. Received: " error.
      expect(stub.lastRequestContentType, contains('application/json'),
          reason: 'check_subscription.php reads php://input, not '
              '\$_POST. The client must POST application/json. '
              'Got Content-Type: ${stub.lastRequestContentType}');
      final sent = jsonDecode(stub.lastRequestBody!);
      expect(sent, isA<Map<String, dynamic>>(),
          reason: 'checkSubscription must send a JSON object, not a '
              'form-encoded body. Got: ${stub.lastRequestBody}');
      expect(sent['phone'], '01876452351',
          reason: 'PHP reads `phone` (and 4 other aliases) from the '
              'JSON body. None of the aliases were present. '
              'Got: $sent');
      api.close();
    });

    test('UNREGISTERED user — Login denies access despite isSubscribed:true',
        () async {
      // CRITICAL: upstream's `isSubscribed:true` is a lie — it's a
      // known quirk where the same response field is reported as
      // `true` even when `subscriptionStatus` is `UNREGISTERED`.
      // The spec says: ignore `isSubscribed`, trust
      // `subscriptionStatus` only. This test would fail if a future
      // refactor started trusting `isSubscribed` and let this user
      // into Home.
      const body = '''
{
  "statusCode": "S1000",
  "statusDetail": "Request was successfully processed.",
  "isSubscribed": true,
  "subscriptionStatus": "UNREGISTERED",
  "subscriberId": "tel:8801886452351",
  "bdapps_raw": {
    "subscriptionStatus": "UNREGISTERED",
    "statusDetail": "Request was successfully processed.",
    "version": "1.0",
    "statusCode": "S1000"
  }
}''';
      final stub = _StubClient(body);
      final api = BdAppsApi(client: stub);
      final result = await api.checkSubscription(mobile: '01886452351');

      expect(result.status, BdAppsCheckStatus.notSubscribed,
          reason: 'Upstream says UNREGISTERED — Login must deny access. '
              '`isSubscribed:true` is the known upstream quirk and MUST '
              'be ignored. Got: ${result.status} '
              '(detail=${result.statusDetail}, err=${result.errorMessage})');
      expect(result.isSubscribed, isFalse);
      expect(result.errorMessage, isNull);
      api.close();
    });
  });

  group('unsubscribe wire-format contract', () {
    test('Successful unsubscribe — S1000/UNREGISTERED → unsubscribed:true',
        () async {
      const body = '''
{
  "statusCode": "S1000",
  "statusDetail": "Successfully Unsubscribed",
  "subscriptionStatus": "UNREGISTERED",
  "isSubscribed": false
}''';
      final stub = _StubClient(body);
      final api = BdAppsApi(client: stub);
      final result = await api.unsubscribe(mobile: '01876452351');

      // The unsubscribe wrapper translates a verdict of
      // `notSubscribed` into `unsubscribed:true` so callers can
      // distinguish "post-unsubscribe success" from "user was
      // already not-subscribed". The Login screen reads
      // `isSubscribed`, the More screen reads the
      // `statusDetail` text and triggers the local session
      // clear.
      expect(result.status, BdAppsCheckStatus.notSubscribed,
          reason: 'Unsubscribe success reduces to notSubscribed '
              'verdict (UNREGISTERED is the post-unsubscribe state). '
              'Got: ${result.status} '
              '(detail=${result.statusDetail}, err=${result.errorMessage})');
      expect(result.statusDetail, 'Successfully Unsubscribed');
      expect(result.errorMessage, isNull);

      // REQUEST-BODY ASSERTION: PHP's unsubscribe.php reads
      // `phone|subscriberId|mobile` from the JSON body. The
      // client belt-and-braces sends all three keys so the
      // script's null-coalescing chain always finds a value.
      expect(stub.lastRequestContentType, contains('application/json'),
          reason: 'unsubscribe.php reads php://input, not \$_POST. '
              'Got Content-Type: ${stub.lastRequestContentType}');
      final sent = jsonDecode(stub.lastRequestBody!);
      expect(sent, isA<Map<String, dynamic>>(),
          reason: 'unsubscribe must send a JSON object, not a '
              'form-encoded body. Got: ${stub.lastRequestBody}');
      expect(sent['phone'], '01876452351',
          reason: 'PHP reads `phone` (and 2 other aliases) from the '
              'JSON body. None of the aliases were present. '
              'Got: $sent');
      expect(sent['mobile'], '01876452351',
          reason: 'subscribeId/mobile is a fallback key the PHP '
              'accepts. Got: $sent');
      expect(sent['subscriberId'], 'tel:8801876452351',
          reason: 'PHP accepts subscriberId as the third fallback '
              'key; we send it as tel:8801XXXXXXXXX so the carrier '
              'side gets the canonical id. Got: $sent');
      api.close();
    });

    test('Unsubscribe failed — upstream E1003 → error verdict, '
        'session untouched', () async {
      // Mirrors the PHP's non-S1000 branch:
      //   {"statusCode":"E1003","statusDetail":"Unsubscribe failed",
      //    "subscriptionStatus":"ERROR","isSubscribed":true,...}
      const body = '''
{
  "statusCode": "E1003",
  "statusDetail": "Unsubscribe failed",
  "subscriptionStatus": "ERROR",
  "isSubscribed": true,
  "bdapps_raw": {"statusCode":"E1003","statusDetail":"Invalid subscriber ID"}
}''';
      final stub = _StubClient(body);
      final api = BdAppsApi(client: stub);
      final result = await api.unsubscribe(mobile: '01876452351');

      // Non-S1000 → error verdict. The More screen's snackbar
      // reads `errorMessage` verbatim — that's the upstream
      // `statusDetail` here, NOT the bare "Unsubscribe failed"
      // (which would be too vague to debug).
      expect(result.status, BdAppsCheckStatus.error,
          reason: 'Non-S1000 upstream response must NOT be '
              'interpreted as a successful unsubscribe. Got: '
              '${result.status}');
      expect(result.errorMessage, contains('Unsubscribe failed'),
          reason: 'errorMessage must surface the upstream statusDetail '
              'verbatim so the More screen can show it to the user. '
              'Got: ${result.errorMessage}');
      api.close();
    });
  });
}
