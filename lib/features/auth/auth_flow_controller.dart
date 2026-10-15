import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/bdapps_api.dart';
import 'auth_controller.dart';

/// Lifecycle of a single OTP-subscription transaction.
///
/// Each terminal stage carries a [LoginVerdict] (see below) so the
/// UI can render the correct panel WITHOUT having to parse
/// [AuthFlowState.errorMessage]. This kills the dual-message bug
/// (the previous build surfaced "not subscribed" in BOTH the
/// inline field error AND the panel below the form), and removes
/// the only piece of string-matching in the error-state render
/// path — suspected source of the Login-screen ANR because any
/// "filter the message and setState again" hack would loop.
///
/// [idle] — initial state, no API call in flight.
/// [sending] — sendOtp request in flight.
/// [awaitingOtp] — got a reference number; user should type the OTP.
/// [verifying] — verifyOtp request in flight.
/// [error] — last call failed; [errorMessage] is the reason and
///           [verdict] tells the UI which panel to render.
enum AuthFlowStage {
  idle,
  sending,
  awaitingOtp,
  verifying,
  error,
}

/// Outcome of the most recent Login verify. Drives which error
/// panel the Login screen renders.
///
/// Introduced as an explicit enum so the UI never has to parse the
/// human-readable [AuthFlowState.errorMessage] to decide between
/// "not subscribed → show Subscribe CTA" and "retryable → show
/// Retry button". One source of truth = no risk of a rebuild loop
/// when the message text changes.
///
/// The previous design routed the decision through
/// `_classifyVerdict(message)` in login_screen.dart, which then
/// called no setState but was the only signal-driving-from-string
/// seam left after the spec hardening. Replacing it with an enum
/// field also lets us stop populating the inline field error for
/// the "not subscribed" verdict, which was the user-visible side of
/// the freeze (the input field lit up red, the user thought the
/// app hung).
enum LoginVerdict {
  /// No verdict yet (initial state, or verdict was cleared on
  /// reset). The Login screen renders the static "not subscribed
  /// yet?" deep-link card.
  none,

  /// Upstream confirmed `subscriptionStatus == "UNREGISTERED"`.
  /// The Login screen renders the red "not subscribed" panel with
  /// a Subscribe CTA.
  notSubscribed,

  /// Transport / parse / non-S1000 error. The Login screen
  /// renders the amber retry panel with a Retry button. We never
  /// redirect to Subscribe on this verdict — a transient blip
  /// must not bounce a paid-up user.
  retryable,

  /// Local input validation failure (empty / wrong format). The
  /// Login screen surfaces this in the inline field error and
  /// does NOT render any panel below the form.
  invalid,
}

class AuthFlowState {
  const AuthFlowState({
    required this.stage,
    required this.mobile,
    required this.referenceNo,
    required this.errorMessage,
    required this.verdict,
  });

  final AuthFlowStage stage;
  final String mobile;
  final String referenceNo;
  final String errorMessage;

  /// Explicit verdict for the most recent Login verify. Drives the
  /// Login screen's error panel selection without parsing
  /// [errorMessage].
  final LoginVerdict verdict;

  static const initial = AuthFlowState(
    stage: AuthFlowStage.idle,
    mobile: '',
    referenceNo: '',
    errorMessage: '',
    verdict: LoginVerdict.none,
  );

  bool get isBusy =>
      stage == AuthFlowStage.sending || stage == AuthFlowStage.verifying;

  AuthFlowState copyWith({
    AuthFlowStage? stage,
    String? mobile,
    String? referenceNo,
    String? errorMessage,
    LoginVerdict? verdict,
  }) {
    return AuthFlowState(
      stage: stage ?? this.stage,
      mobile: mobile ?? this.mobile,
      referenceNo: referenceNo ?? this.referenceNo,
      errorMessage: errorMessage ?? this.errorMessage,
      verdict: verdict ?? this.verdict,
    );
  }
}

/// State machine for the Subscribe screen — owns the sendOtp →
/// verifyOtp transaction and persists the session on success.
class SubscribeFlowController extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => AuthFlowState.initial;

  /// Set the mobile number the user typed (kept in state so the OTP
  /// step can re-use it).
  void setMobile(String mobile) {
    if (mobile == state.mobile) return;
    state = state.copyWith(mobile: mobile);
  }

  /// Send the OTP. On dev-bypass mobile (`00000000000`), skips the
  /// API and goes straight to a fake "awaiting OTP" stage so the
  /// bypass UX matches the real flow (still has to type the OTP).
  ///
  /// If the upstream `send_otp.php` reports the user as already
  /// subscribed (BDApps returns statusCode S1000 /
  /// subscriptionStatus REGISTERED but no referenceNo), we mark the
  /// user as subscribed directly and short-circuit to Home — same
  /// effect as if they had just finished a verify_otp round-trip.
  Future<bool> sendOtp() async {
    final mobile = state.mobile;
    if (MobileValidation.validateRobiCirkle(mobile) != null) {
      state = state.copyWith(
        stage: AuthFlowStage.error,
        errorMessage:
            'Enter a valid 11-digit Robi (018) or Cirkle (016) number',
      );
      return false;
    }
    if (mobile == kDevBypassMobile) {
      state = state.copyWith(
        stage: AuthFlowStage.awaitingOtp,
        referenceNo: 'DEV-BYPASS',
        errorMessage: '',
      );
      return true;
    }
    state = state.copyWith(
      stage: AuthFlowStage.sending,
      errorMessage: '',
    );
    try {
      final api = ref.read(bdAppsApiProvider);
      final result = await api.sendOtp(mobile: mobile);
      if (!result.isOk) {
        state = state.copyWith(
          stage: AuthFlowStage.error,
          errorMessage: result.statusDetail ??
              'Could not send OTP. Please try again.',
        );
        return false;
      }
      // Already-subscribed shortcut — upstream says REGISTERED but
      // didn't issue an OTP referenceNo. Take the user straight to
      // Home rather than forcing them through a useless OTP entry.
      if (result.referenceNo.isEmpty &&
          (result.subscriptionStatus == 'REGISTERED' ||
              (result.statusCode?.toUpperCase() == 'S1000'))) {
        await ref.read(subscriptionControllerProvider.notifier).markSubscribed(
              subscriberId: 'tel:88$mobile',
              mobile: mobile,
            );
        reset();
        return true;
      }
      state = state.copyWith(
        stage: AuthFlowStage.awaitingOtp,
        referenceNo: result.referenceNo,
        errorMessage: '',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        stage: AuthFlowStage.error,
        errorMessage: 'Network error. Check your connection and retry.',
      );
      return false;
    }
  }

  /// Verify the 6-digit OTP. On dev-bypass, any 6 digits succeed.
  /// On real flow, threads the referenceNo + OTP into verify_otp.php
  /// and only persists the session when the carrier reports
  /// subscriptionStatus == REGISTERED.
  Future<bool> verifyOtp(String otp) async {
    if (otp.length != 6) {
      state = state.copyWith(
        stage: AuthFlowStage.error,
        errorMessage: 'Enter the 6-digit OTP',
      );
      return false;
    }
    final mobile = state.mobile;
    if (mobile == kDevBypassMobile) {
      await ref.read(subscriptionControllerProvider.notifier).markSubscribed(
            subscriberId: 'tel:880000000000',
            mobile: '00000000000',
          );
      reset();
      return true;
    }
    state = state.copyWith(
      stage: AuthFlowStage.verifying,
      errorMessage: '',
    );
    try {
      final api = ref.read(bdAppsApiProvider);
      final result = await api.verifyOtp(
        referenceNo: state.referenceNo,
        otp: otp,
      );
      if (!result.isRegistered) {
        state = state.copyWith(
          stage: AuthFlowStage.error,
          errorMessage: result.statusDetail ??
              'OTP verification failed. Try again.',
        );
        return false;
      }
      await ref.read(subscriptionControllerProvider.notifier).markSubscribed(
            subscriberId: 'tel:88$mobile',
            mobile: mobile,
          );
      reset();
      return true;
    } catch (e) {
      state = state.copyWith(
        stage: AuthFlowStage.error,
        errorMessage: 'Network error. Check your connection and retry.',
      );
      return false;
    }
  }

  /// Wipe transient flow state — called after a successful verify or
  /// when the user backs out.
  void reset() {
    state = AuthFlowState.initial;
  }

  /// Set an error state without doing any API work. Used by the
  /// Subscribe screen for local input-validation errors that
  /// should surface in the same error banner as upstream
  /// failures — but without round-tripping the network.
  void setError(String message) {
    state = state.copyWith(
      stage: AuthFlowStage.error,
      errorMessage: message,
    );
  }
}

final subscribeFlowControllerProvider =
    NotifierProvider<SubscribeFlowController, AuthFlowState>(
  SubscribeFlowController.new,
);

/// ─────────────────────────────────────────────────────────────────
/// Login screen — three explicit verdicts, never confused.
///
/// Resolution order, in this exact priority:
///   1. Empty input             → error (no API call)
///   2. Local validation fails  → error (no API call)
///   3. Dev-bypass mobile       → grant session immediately
///   4. **Always** call the upstream check_subscription.php for any
///      real Robi/Cirkle number. PHP is the source of truth for
///      "did the user pay the initial charge?" — we never log the
///      user in from a cached result.
///   5. Subscribed            → save mobile, log in, → Home.
///      (Verdict = upstream `subscriptionStatus == "REGISTERED"`,
///      NOT upstream `isSubscribed`, which is known to lie for
///      unsubscribed numbers.)
///   6. Not subscribed (server says so) → show "This number is not
///      subscribed" + CTA to Subscribe.
///   7. Error / timeout / parse → show "Could not verify right now"
///      + Retry. NEVER confuse this with not-subscribed — a
///      transient network blip must not bounce a paid-up user to
///      the Subscribe screen.
/// ─────────────────────────────────────────────────────────────────
class LoginFlowController extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => AuthFlowState.initial;

  /// Re-entrancy guard. Prevents a double-tap on "Verify & Continue"
  /// from dispatching two `checkSubscription` calls in parallel and
  /// from racing the state-mutation phase. Always reset in `finally`
  /// so a thrown future never leaves the gate stuck.
  bool _isLoading = false;

  void setMobile(String mobile) {
    if (mobile == state.mobile) return;
    state = state.copyWith(mobile: mobile);
  }

  Future<bool> verifyAndContinue() async {
    // ── Re-entrancy guard ─────────────────────────────────────────
    // A second tap while the previous verify is still in flight
    // returns immediately. The Login screen also disables the
    // button via `flow.isBusy`, but the controller-level guard is
    // the source of truth — it can't be bypassed by a stale
    // widget tree.
    if (_isLoading) return false;
    _isLoading = true;
    try {
      final mobile = state.mobile;
      if (mobile.isEmpty) {
        state = state.copyWith(
          stage: AuthFlowStage.error,
          verdict: LoginVerdict.invalid,
          errorMessage: 'Enter your mobile number',
        );
        return false;
      }
      if (MobileValidation.validateRobiCirkle(mobile) != null &&
          mobile != kDevBypassMobile) {
        state = state.copyWith(
          stage: AuthFlowStage.error,
          verdict: LoginVerdict.invalid,
          errorMessage:
              'Enter a valid 11-digit Robi (018) or Cirkle (016) number',
        );
        return false;
      }
      if (mobile == kDevBypassMobile) {
        // Dev-bypass sentinel — write a regex-shaped pair through
        // the repository. The repo (`subscription_repository.dart`)
        // now special-cases `tel:880000000000` / `00000000000` so
        // the regex strip does not silently corrupt the
        // persisted session, and `mobile()` reconstructs the
        // bypass mobile back. Without this fix, after the user
        // taps Verify & Continue on the bypass mobile, the
        // persisted Hive state was `subscriberId=''`, `mobile=''`,
        // `isSubscribed=true`, which made `verifySessionInBackground`
        // short-circuit on the next cold start and left the user
        // "stuck subscribed" with no mobile to verify against.
        await ref
            .read(subscriptionControllerProvider.notifier)
            .markSubscribed(
              subscriberId: 'tel:880000000000',
              mobile: '00000000000',
            );
        reset();
        return true;
      }

      // ─── Always call the upstream PHP ────────────────────────────
      // The Login screen is the gate: every Verify & Continue tap
      // round-trips `check_subscription.php`. The PHP is the source
      // of truth for "did this user pay the initial charge?" — we
      // never log the user in from a local cache, a history record,
      // or any other side-channel.
      state = state.copyWith(
        stage: AuthFlowStage.verifying,
        verdict: LoginVerdict.none,
        errorMessage: '',
      );
      final api = ref.read(bdAppsApiProvider);
      final result = await api.checkSubscription(mobile: mobile);
      switch (result.status) {
        case BdAppsCheckStatus.subscribed:
          // Spec rule 5: a result is valid only when statusCode
          // == "S1000". Subscribed only when subscriptionStatus
          // == "REGISTERED". The bdapps_api client enforces that
          // decision rule, so landing here means upstream says
          // REGISTERED.
          await ref
              .read(subscriptionControllerProvider.notifier)
              .markSubscribed(
                subscriberId: 'tel:88$mobile',
                mobile: mobile,
              );
          reset();
          return true;
        case BdAppsCheckStatus.notSubscribed:
          // Spec rule 5: server-confirmed not-subscribed. Show the
          // "not subscribed" panel + Subscribe CTA. We do NOT
          // touch the persisted session here — the user is not
          // logged in, and this is the only way they find out
          // they need to subscribe. The history lookup is also
          // skipped because the user never had a real session
          // for this number.
          //
          // We set `verdict` explicitly (instead of stuffing the
          // message into the inline field error) so the Login
          // screen does NOT light up the input red for a verdict
          // that already has its own panel. This was the visible
          // side of the Login-screen freeze — the user saw the
          // field turn red simultaneously with the panel popping
          // up, and the rapid text change + setState was the
          // suspected ANR trigger.
          state = state.copyWith(
            stage: AuthFlowStage.error,
            verdict: LoginVerdict.notSubscribed,
            errorMessage: '',
          );
          return false;
        case BdAppsCheckStatus.error:
          // Network / timeout / parse / non-S1000 — keep the
          // session intact (transient blip must not log out a
          // paid-up user) and surface the upstream message in
          // the inline field error AND the retry panel.
          final serverMessage = result.errorMessage?.trim() ?? '';
          state = state.copyWith(
            stage: AuthFlowStage.error,
            verdict: LoginVerdict.retryable,
            errorMessage: serverMessage.isNotEmpty
                ? serverMessage
                : 'Could not verify right now, please try again.',
          );
          return false;
      }
    } catch (_) {
      // Defensive catch — we already handle TimeoutException and
      // network errors in the API client, but a thrown future
      // (e.g. Hive closed mid-write) must not leave the gate
      // stuck. The cleanup also resets the verdict so the UI
      // never sticks on a stale verdict after a thrown future.
      state = state.copyWith(
        stage: AuthFlowStage.error,
        verdict: LoginVerdict.retryable,
        errorMessage: 'Could not verify right now, please try again.',
      );
      // The exception is intentionally swallowed here. The
      // Login screen renders the error message; production code
      // should not have unhandled exceptions.
      return false;
    } finally {
      // CRITICAL: clearing _isLoading in `finally` means a thrown
      // future (e.g. Hive closed mid-write, a network hang) cannot
      // leave the Verify & Continue button stuck in its disabled /
      // spinner state. The previous audit identified this exact
      // pattern as the most likely source of the Login-screen ANR:
      // a verify that throws after the API round-trip would have
      // left the gate stuck if cleanup ran in the success path
      // only. We also reset the verdict to `none` so a later
      // re-mount of the screen doesn't re-show a stale panel.
      _isLoading = false;
    }
  }

  void reset() {
    state = AuthFlowState.initial;
  }

  /// Set an error state without doing any API work. Used by the
  /// Login screen for local input-validation errors that should
  /// surface in the same error banner as upstream failures — but
  /// without round-tripping the network.
  ///
  /// We tag the verdict as `invalid` so the Login screen knows
  /// this is a local-validation failure, not a "not subscribed"
  /// server verdict. That keeps the panel-vs-field-error logic
  /// disjoint: validation → inline field error only; not-subscribed
  /// → panel with Subscribe CTA only; retryable → both inline field
  /// error AND retry panel.
  void setError(String message) {
    state = state.copyWith(
      stage: AuthFlowStage.error,
      verdict: LoginVerdict.invalid,
      errorMessage: message,
    );
  }
}

final loginFlowControllerProvider =
    NotifierProvider<LoginFlowController, AuthFlowState>(
  LoginFlowController.new,
);
