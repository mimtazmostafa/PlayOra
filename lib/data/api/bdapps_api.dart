import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thin REST client for the PlayNest bdapps subscription gateway
/// hosted at `https://ruetandroiddevelopers.com/PlayNest/`.
///
/// Endpoints:
///   * [sendOtp]            — kicks off a subscription / OTP flow.
///   * [verifyOtp]          — finalises the subscription with the 6-digit code.
///   * [checkSubscription]  — Login screen + session check: "is this
///                            mobile currently subscribed?".
///   * [unsubscribe]        — cancels the carrier-side subscription.
///
/// All endpoints accept `application/x-www-form-urlencoded` bodies
/// (the upstream PHP scripts read from `$_POST`), so we use
/// [http.post] with `body:` rather than a JSON envelope.
///
/// The two `success`/`error` endpoints — [checkSubscription] and
/// [unsubscribe] — share an identical decision rule:
///   * A response is **valid** ONLY when `statusCode == "S1000"`
///     AND `subscriptionStatus` is non-empty.
///   * The user is **subscribed** ONLY when
///     `subscriptionStatus == "REGISTERED"`. `isSubscribed` is
///     explicitly NOT trusted (it is occasionally wrong on the
///     upstream side).
///   * Anything else is an error — the upstream `message` is
///     surfaced verbatim to the UI.
class BdAppsApi {
  BdAppsApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? 'https://ruetandroiddevelopers.com/PlayNest/';

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 15);

  // ─────────────────────────────────────────────────────────────
  // OTP flow (Subscribe screen) — preserves the existing contract.
  // ─────────────────────────────────────────────────────────────

  /// Result of [sendOtp]. `referenceNo` is what the upstream returns
  /// and must be threaded back into [verifyOtp].
  Future<BdAppsOtpRequest> sendOtp({required String mobile}) async {
    final uri = Uri.parse('${_baseUrl}send_otp.php');
    _logRequest('→ POST $uri', {'user_mobile': mobile});
    final res = await _client
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {'user_mobile': mobile},
        )
        .timeout(_timeout);
    _logResponse('← POST $uri', res);
    return _decode(res, BdAppsOtpRequest.fromJson, fallback: () {
      return BdAppsOtpRequest(
        referenceNo: '',
        statusCode: 'E0000',
        statusDetail:
            res.body.isEmpty ? 'Empty response from server' : res.body,
      );
    });
  }

  /// Result of [verifyOtp]. The key signal is
  /// [BdAppsOtpVerifyResult.subscriptionStatus] — REGISTERED means
  /// the user is now subscribed and may proceed into the app.
  Future<BdAppsOtpVerifyResult> verifyOtp({
    required String referenceNo,
    required String otp,
  }) async {
    final uri = Uri.parse('${_baseUrl}verify_otp.php');
    _logRequest('→ POST $uri', {'referenceNo': referenceNo, 'Otp': otp});
    final res = await _client
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {
            'referenceNo': referenceNo,
            'Otp': otp,
          },
        )
        .timeout(_timeout);
    _logResponse('← POST $uri', res);
    return _decode(
      res,
      BdAppsOtpVerifyResult.fromJson,
      fallback: () => BdAppsOtpVerifyResult(
        subscriptionStatus: 'ERROR',
        statusCode: 'E0000',
        statusDetail:
            res.body.isEmpty ? 'Empty response from server' : res.body,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Login + session-check endpoint.
  // ─────────────────────────────────────────────────────────────

  /// Hits the upstream `check_subscription.php`. This is the
  /// authoritative Login-time check: every Verify & Continue tap on
  /// the Login screen round-trips this endpoint, AND the
  /// background session check on app start / resume round-trips
  /// it too. The Flutter side does NOT cache the result.
  ///
  /// Returns a [BdAppsCheckResult] with three explicit verdicts:
  ///   * [BdAppsCheckStatus.subscribed]   — statusCode==S1000 AND
  ///                                        subscriptionStatus==REGISTERED.
  ///   * [BdAppsCheckStatus.notSubscribed]— statusCode==S1000 AND
  ///                                        subscriptionStatus=="UNREGISTERED".
  ///   * [BdAppsCheckStatus.error]        — anything else (network /
  ///                                        timeout / parse / statusCode
  ///                                        != S1000 / empty
  ///                                        subscriptionStatus). The
  ///                                        Login screen must NEVER
  ///                                        confuse this with
  ///                                        `notSubscribed`.
  Future<BdAppsCheckResult> checkSubscription({
    required String mobile,
  }) async {
    final uri = Uri.parse('${_baseUrl}check_subscription.php');
    // PHP-side contract (server reads `php://input`, NOT `$_POST`):
    //
    //   $rawMobile = $input['phone'] ?? $input['mobile']
    //             ?? $input['subscriberId'] ?? $input['phoneNumber']
    //             ?? $input['msisdn'] ?? '';
    //
    // The script rejects anything that doesn't normalise to a
    // 11-digit `01[68]xxxxxxxx` Robi/Cirkle number — so if we send
    // a form-encoded `user_mobile=...` body the script leaves
    // `$rawMobile` empty and answers with `E0000 / "Invalid mobile
    // number format. Received: "` (the user saw exactly this in
    // the field after the Login-screen freeze fix). Sending JSON
    // with `phone` (one of the accepted keys) is the correct wire
    // format.
    _logRequest('→ POST $uri', {'phone': mobile});

    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            // Belt-and-braces: include every key the PHP
            // check_subscription.php accepts (`phone`, `mobile`,
            // `subscriberId`, `phoneNumber`, `msisdn`) so a future
            // server-side tweak doesn't bounce a real Robi/Cirkle
            // number back as "Invalid mobile number format".
            body: jsonEncode({
              'phone': mobile,
              'mobile': mobile,
              'subscriberId': 'tel:88$mobile',
              'phoneNumber': mobile,
              'msisdn': mobile,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      _logError('timeout after $_timeout', uri);
      return BdAppsCheckResult.error(
        message: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      _logError('network error: $e', uri);
      return BdAppsCheckResult.error(
        message: 'Network error. Check your connection and try again.',
      );
    }

    // Spec requires the raw response body to be printed in debug
    // builds with the [BdAppsClient.CHECK_SUB] tag.
    _logBody('[BdAppsClient.CHECK_SUB]', res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return BdAppsCheckResult.error(
        message: 'Server returned ${res.statusCode}',
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return BdAppsCheckResult.error(
          message: 'Unexpected response shape from server',
        );
      }
      json = decoded;
    } on FormatException {
      return BdAppsCheckResult.error(
        message: 'Could not parse server response',
      );
    }

    return _verdictFromJson(json);
  }

  // ─────────────────────────────────────────────────────────────
  // Unsubscribe endpoint.
  // ─────────────────────────────────────────────────────────────

  /// Hits the upstream `unsubscribe.php` with the saved mobile
  /// number. Carries the same verdict semantics as
  /// [checkSubscription]:
  ///   * statusCode==S1000 AND subscriptionStatus==UNREGISTERED
  ///     → [BdAppsCheckStatus.notSubscribed] (the carrier
  ///       confirmation SMS is sent by BDApps itself — the app
  ///       does nothing else).
  ///   * anything else → [BdAppsCheckStatus.error], upstream
  ///     `message` surfaced verbatim.
  Future<BdAppsCheckResult> unsubscribe({
    required String mobile,
  }) async {
    final uri = Uri.parse('${_baseUrl}unsubscribe.php');
    // PHP-side contract (server reads `php://input`, NOT `$_POST`):
    //
    //   $rawMobile = $request['phone'] ?? $request['subscriberId']
    //             ?? $request['mobile'] ?? $_POST['subscriberId']
    //             ?? '';
    //
    // Same shape as check_subscription.php — if we send a
    // form-encoded `user_mobile=...` body the script leaves
    // `$rawMobile` empty and answers with `E1000 / "Invalid mobile
    // number format"`, which our client surfaces verbatim. Sending
    // JSON with `phone` (one of the accepted keys) is the correct
    // wire format.
    _logRequest('→ POST $uri', {'phone': mobile});

    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            // Same belt-and-braces as checkSubscription: include
            // every key the PHP unsubscribe.php accepts (`phone`,
            // `mobile`, `subscriberId`) so the script's
            // null-coalescing chain always finds a real number.
            body: jsonEncode({
              'phone': mobile,
              'mobile': mobile,
              'subscriberId': 'tel:88$mobile',
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      _logError('unsubscribe: timeout after $_timeout', uri);
      return BdAppsCheckResult.error(
        message: 'Request timed out. Check your connection and try again.',
      );
    } catch (e) {
      _logError('unsubscribe: network error: $e', uri);
      return BdAppsCheckResult.error(
        message: 'Network error. Check your connection and try again.',
      );
    }

    // Spec requires the raw response body to be printed in debug
    // builds with the [BdAppsClient.UNSUB] tag.
    _logBody('[BdAppsClient.UNSUB]', res.body);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      return BdAppsCheckResult.error(
        message: 'Server returned ${res.statusCode}',
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return BdAppsCheckResult.error(
          message: 'Unexpected response shape from server',
        );
      }
      json = decoded;
    } on FormatException {
      return BdAppsCheckResult.error(
        message: 'Could not parse server response',
      );
    }

    final result = _verdictFromJson(json);
    // Unsubscribe's spec-shaped success uses
    // `subscriptionStatus:"UNREGISTERED"` (no registered value),
    // so the verdict comes back as `notSubscribed`. Translate that
    // to the explicit unsubscribe-success message callers expect.
    if (result.status == BdAppsCheckStatus.notSubscribed) {
      return BdAppsCheckResult.success(
        unsubscribed: true,
        statusDetail: result.statusDetail ?? 'Successfully Unsubscribed',
      );
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // Shared verdict logic for checkSubscription + unsubscribe.
  // ─────────────────────────────────────────────────────────────

  /// Apply the spec's decision rule to a decoded JSON object:
  ///   * valid AND `subscriptionStatus == "REGISTERED"` → subscribed
  ///   * valid AND anything else                      → notSubscribed
  ///   * invalid                                       → error
  /// "valid" = `statusCode == "S1000"` AND `subscriptionStatus`
  /// is non-empty.
  BdAppsCheckResult _verdictFromJson(Map<String, dynamic> json) {
    final statusCode =
        json['statusCode']?.toString().toUpperCase() ?? '';
    final subStatus =
        json['subscriptionStatus']?.toString().toUpperCase() ?? '';
    final statusDetail =
        (json['statusDetail']?.toString() ?? '').trim();
    final upstreamMessage =
        (json['message']?.toString() ?? '').trim();

    final ok = statusCode == 'S1000' && subStatus.isNotEmpty;

    if (ok && subStatus == 'REGISTERED') {
      return BdAppsCheckResult.success(
        unsubscribed: false,
        statusDetail: statusDetail,
      );
    }

    if (ok && subStatus != 'REGISTERED') {
      // Valid response but the user is not currently subscribed.
      // Includes "UNREGISTERED" (most common), but be permissive
      // about other off-status values too.
      return BdAppsCheckResult.success(
        unsubscribed: true,
        statusDetail: statusDetail,
      );
    }

    // Invalid → error. Show the upstream's `message` verbatim when
    // present; fall back to `statusDetail`; fall back to a generic
    // transport-failure note.
    final message = upstreamMessage.isNotEmpty
        ? upstreamMessage
        : statusDetail.isNotEmpty
            ? statusDetail
            : 'Could not verify right now, please try again.';
    return BdAppsCheckResult.error(message: message);
  }

  void close() => _client.close();

  // ─────────────────────────────────────────────────────────────
  // Logging + decoding helpers.
  // ─────────────────────────────────────────────────────────────

  T _decode<T>(
    http.Response res,
    T Function(Map<String, dynamic>) fromJson, {
    required T Function() fallback,
  }) {
    if (res.body.isEmpty) return fallback();
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {
      // fall through to fallback
    }
    return fallback();
  }

  void _logRequest(String line, Object body) {
    if (!kDebugMode) return;
    developer.log('$line  body=$body', name: 'BdAppsClient');
  }

  void _logResponse(String line, http.Response res) {
    if (!kDebugMode) return;
    developer.log('$line  status=${res.statusCode}  body=${res.body}',
        name: 'BdAppsClient');
  }

  void _logError(String message, Uri uri) {
    if (!kDebugMode) return;
    developer.log('✗ $uri  $message', name: 'BdAppsClient');
  }

  /// Print the raw upstream JSON to the in-app dev console with
  /// the spec-mandated tag.
  void _logBody(String tag, String body) {
    if (!kDebugMode) return;
    developer.log('$tag $body', name: 'BdAppsClient');
  }
}

// ─────────────────────────────────────────────────────────────────
// Login + Unsubscribe result types.
//
// spec rules:
//   * valid  ⇔ statusCode=="S1000" AND subscriptionStatus is non-empty
//   * subscribed ⇔ subscriptionStatus=="REGISTERED"
//   * anything else = error
//
// The unsubscribe endpoint's success path returns
// `subscriptionStatus:"UNREGISTERED"`, which our decision rule
// encodes as `status: notSubscribed` (the user is *definitely*
// not currently subscribed — this is the post-unsubscribe state).
// That is intentional: the same data structure drives both flows.
// ─────────────────────────────────────────────────────────────────

/// Three-way verdict returned by both `checkSubscription` and
/// `unsubscribe`. Spec guarantees no fourth state — every
/// upstream response falls into exactly one of these.
enum BdAppsCheckStatus {
  /// statusCode==S1000 AND subscriptionStatus=="REGISTERED".
  subscribed,

  /// statusCode==S1000 AND subscriptionStatus is anything other
  /// than REGISTERED (typically "UNREGISTERED" — covers both
  /// "log-in user is currently not subscribed" and
  /// "post-unsubscribe success").
  notSubscribed,

  /// Anything else — network / timeout / parse / statusCode
  /// non-S1000 / empty subscriptionStatus. The upstream `message`
  /// is surfaced verbatim so the Login screen + Unsubscribe flow
  /// can render an honest Retry button without confusing it with
  /// "not subscribed".
  error,
}

/// Typed result of [BdAppsApi.checkSubscription] and
/// [BdAppsApi.unsubscribe]. Always carries either a
/// [statusDetail] (on success) or an [errorMessage] (on error),
/// so the UI never has to deal with empty copy.
class BdAppsCheckResult {
  const BdAppsCheckResult._({
    required this.status,
    this.statusDetail,
    this.errorMessage,
  });

  /// Successful "user is currently subscribed" verdict.
  /// Used for [BdAppsApi.checkSubscription] when
  /// `subscriptionStatus == "REGISTERED"`.
  factory BdAppsCheckResult.success({
    required bool unsubscribed,
    required String statusDetail,
  }) =>
      BdAppsCheckResult._(
        status: unsubscribed
            ? BdAppsCheckStatus.notSubscribed
            : BdAppsCheckStatus.subscribed,
        statusDetail: statusDetail,
      );

  /// Success-but-not-subscribed verdict. Two entry points:
  ///   * `checkSubscription` returning `UNREGISTERED`.
  ///   * `unsubscribe` returning its S1000 success shape.
  /// (Both reduce to the same wire shape; we surface them
  /// through one constructor for symmetry.)
  factory BdAppsCheckResult.notSubscribedDetail(String statusDetail) =>
      BdAppsCheckResult._(
        status: BdAppsCheckStatus.notSubscribed,
        statusDetail: statusDetail,
      );

  /// Transport / upstream error. [errorMessage] is the user-facing
  /// copy — prefers the upstream `message` field, falls back to
  /// `statusDetail`, finally to a generic transport-failure note.
  factory BdAppsCheckResult.error({required String message}) =>
      BdAppsCheckResult._(
        status: BdAppsCheckStatus.error,
        errorMessage: message,
      );

  final BdAppsCheckStatus status;
  final String? statusDetail;
  final String? errorMessage;

  bool get isSubscribed => status == BdAppsCheckStatus.subscribed;
  bool get isNotSubscribed => status == BdAppsCheckStatus.notSubscribed;
  bool get isError => status == BdAppsCheckStatus.error;

  @override
  String toString() =>
      'BdAppsCheckResult(status: $status, statusDetail: $statusDetail, '
      'errorMessage: $errorMessage)';
}

// ─────────────────────────────────────────────────────────────────
// OTP flow types — left intact for the (working) Subscribe screen.
// ─────────────────────────────────────────────────────────────────

/// Payload returned by `send_otp.php`.
class BdAppsOtpRequest {
  const BdAppsOtpRequest({
    required this.referenceNo,
    this.statusCode,
    this.statusDetail,
    this.subscriptionStatus,
    this.hasError = false,
  });

  factory BdAppsOtpRequest.fromJson(Map<String, dynamic> json) {
    final code = json['statusCode']?.toString();
    final detail = json['statusDetail']?.toString();
    final subStatus =
        json['subscriptionStatus']?.toString().toUpperCase() ?? '';
    final hasErrorCode = code != null &&
        code.isNotEmpty &&
        code.toUpperCase().startsWith('E');
    final hasErrorSubStatus = subStatus == 'ERROR';
    final hasExplicitError = hasErrorCode || hasErrorSubStatus;
    return BdAppsOtpRequest(
      referenceNo: json['referenceNo']?.toString() ?? '',
      statusCode: code,
      statusDetail: detail,
      subscriptionStatus: subStatus.isEmpty ? null : subStatus,
      hasError: hasExplicitError,
    );
  }

  final String referenceNo;
  final String? statusCode;
  final String? statusDetail;
  final String? subscriptionStatus;
  final bool hasError;

  bool get isOk {
    if (hasError) return false;
    if (referenceNo.isNotEmpty) return true;
    if (statusCode != null && statusCode!.toUpperCase() == 'S1000') {
      return true;
    }
    if (subscriptionStatus != null && subscriptionStatus == 'REGISTERED') {
      return true;
    }
    return false;
  }

  bool get hasFreshOtpTransaction =>
      !hasError && referenceNo.isNotEmpty;

  bool get looksAlreadySubscribed {
    if (hasError) return false;
    if (referenceNo.isNotEmpty) return false;
    if (statusCode == null) return false;
    return statusCode!.toUpperCase() == 'S1000' ||
        subscriptionStatus == 'REGISTERED';
  }
}

/// Payload returned by `verify_otp.php`.
class BdAppsOtpVerifyResult {
  const BdAppsOtpVerifyResult({
    required this.subscriptionStatus,
    this.statusCode,
    this.statusDetail,
  });

  factory BdAppsOtpVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawSub = json['subscriptionStatus']?.toString() ?? '';
    final code = json['statusCode']?.toString();
    final subStatus = rawSub.isNotEmpty ? rawSub.toUpperCase() : '';
    return BdAppsOtpVerifyResult(
      subscriptionStatus: subStatus,
      statusCode: code,
      statusDetail: json['statusDetail']?.toString(),
    );
  }

  final String subscriptionStatus;
  final String? statusCode;
  final String? statusDetail;

  bool get isRegistered =>
      subscriptionStatus == 'REGISTERED' ||
      (statusCode != null && statusCode!.toUpperCase() == 'S1000');
}
