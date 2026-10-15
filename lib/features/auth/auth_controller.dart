import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/bdapps_api.dart';
import '../../data/repositories/subscription_repository.dart';

/// Provider for the upstream bdapps REST client. Override in `main.dart`
/// with the production impl (or a fake HTTP client in tests).
final bdAppsApiProvider = Provider<BdAppsApi>((ref) {
  throw UnimplementedError(
    'bdAppsApiProvider must be overridden in ProviderScope',
  );
});

/// Provider for [SubscriptionRepository]. Overridden in `main.dart`
/// with the Hive-backed implementation; tests override with the
/// in-memory one.
final subscriptionRepositoryProvider =
    Provider<SubscriptionRepository>((ref) {
  throw UnimplementedError(
    'subscriptionRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Reactive snapshot of the local subscription session. The router
/// listens to this to decide whether to land the user on Subscribe,
/// Login, or Home.
class SubscriptionController extends Notifier<SubscriptionState> {
  late final SubscriptionRepository _repo;

  @override
  SubscriptionState build() {
    _repo = ref.read(subscriptionRepositoryProvider);
    return _readFromRepo();
  }

  SubscriptionState _readFromRepo() {
    final subId = _repo.subscriberId();
    final mobile = _repo.mobile();
    final subscribed = _repo.isSubscribed();
    return SubscriptionState(
      subscriberId: subId,
      mobile: mobile,
      isSubscribed: subscribed,
      lastVerifiedAtMs: _repo.lastVerifiedAtMs(),
    );
  }

  /// Persist a freshly verified subscription and broadcast the new
  /// state to listeners.
  Future<void> markSubscribed({
    required String subscriberId,
    required String mobile,
  }) async {
    await _repo.setSession(
      subscriberId: subscriberId,
      mobile: mobile,
      isSubscribed: true,
    );
    state = _readFromRepo();
  }

  /// Clear the local session without touching the carrier — used by
  /// the Logout button. The logout-safe subscription history
  /// (per-device list of previously-subscribed mobiles) is preserved
  /// so a returning user on the same device can still be recognised
  /// on Login even when the upstream `getStatus` call is mis-reporting
  /// their subscription.
  Future<void> logout() async {
    await _repo.clearSession();
    state = _readFromRepo();
  }

  /// Drop a specific mobile from the subscription history — called
  /// after a successful Unsubscribe so a user who cancels carrier-side
  /// is properly forgotten.
  Future<void> forgetMobile(String mobile) async {
    await _repo.forgetMobile(mobile);
  }

  /// Background session re-verification.
  ///
  /// Called on app start (after Hive init) and on resume, but
  /// **only** when the saved session hasn't been re-verified within
  /// the last [_backgroundReverifyAfter] — otherwise we'd hammer
  /// the upstream on every foreground.
  ///
  /// Resolution matches the Login screen rules (rule 5):
  ///   * success + subscribed        → keep session (do nothing).
  ///   * success + notSubscribed     → clear saved session + flip
  ///                                   `isSubscribed` to false so the
  ///                                   router bounces the user to
  ///                                   /login.
  ///   * error / timeout / offline   → keep the user logged in.
  ///                                   A transient network blip must
  ///                                   not kick a paid-up user out.
  ///   * no saved session            → no-op.
  Future<void> verifySessionInBackground({
    Duration debounce = _backgroundReverifyAfter,
    DateTime? now,
  }) async {
    final session = _readFromRepo();
    if (!session.isSubscribed || session.mobile.isEmpty) {
      return;
    }
    final clock = now ?? DateTime.now();
    final lastVerified = DateTime.fromMillisecondsSinceEpoch(
      session.lastVerifiedAtMs == 0 ? 0 : session.lastVerifiedAtMs,
    );
    final age = clock.difference(lastVerified);
    if (lastVerified.millisecondsSinceEpoch != 0 && age < debounce) {
      developer.log(
        'background verify: skipped (last verified $age ago < $debounce)',
        name: 'AuthFlow',
      );
      return;
    }
    final api = ref.read(bdAppsApiProvider);
    developer.log(
      'background verify: checkSubscription("${session.mobile}") '
      '(last verified $age ago)',
      name: 'AuthFlow',
    );
    final result = await api.checkSubscription(mobile: session.mobile);
    switch (result.status) {
      case BdAppsCheckStatus.subscribed:
        // Server still says REGISTERED — refresh the local
        // lastVerifiedAtMs so the next debounce window starts now.
        // Use the existing setSession path so the rest of the
        // pipeline (history record) stays in sync.
        await _repo.setSession(
          subscriberId: session.subscriberId,
          mobile: session.mobile,
          isSubscribed: true,
        );
        state = _readFromRepo();
        developer.log(
          'background verify: still subscribed — kept logged in',
          name: 'AuthFlow',
        );
        return;
      case BdAppsCheckStatus.notSubscribed:
        // Server says the subscription is no longer on file. Clear
        // the local session so the router bounces the user to Login.
        // We do NOT call logout() because that's wired to the More
        // tab's logout UX; here we want a quieter clear that
        // doesn't show toast/redirect immediately. clearSession +
        // state refresh is enough — the auth gate in app_router.dart
        // will redirect on the next state tick.
        await _repo.clearSession();
        state = _readFromRepo();
        developer.log(
          'background verify: NOT subscribed — cleared local session',
          name: 'AuthFlow',
        );
        return;
      case BdAppsCheckStatus.error:
        // Network blip — do nothing. Keep the user logged in.
        developer.log(
          'background verify: error (${result.errorMessage ?? 'unknown'}) '
          '— kept logged in',
          name: 'AuthFlow',
        );
        return;
    }
  }

  /// How stale a session may be before a background re-check fires.
  /// Spec calls for "every app start, and on resume after a few
  /// hours" — we use 1 hour as a sensible minimum to avoid hammering
  /// the upstream when the user just briefly swipes back into the
  /// app.
  static const Duration _backgroundReverifyAfter = Duration(hours: 1);
}

class SubscriptionState {
  const SubscriptionState({
    required this.subscriberId,
    required this.mobile,
    required this.isSubscribed,
    required this.lastVerifiedAtMs,
  });

  /// Empty / unauthenticated state — used as the initial value while
  /// Hive is still loading.
  static const empty = SubscriptionState(
    subscriberId: '',
    mobile: '',
    isSubscribed: false,
    lastVerifiedAtMs: 0,
  );

  /// `tel:88xxxxxxxxxx` carrier-side id, empty when no session.
  final String subscriberId;

  /// Bangladeshi 11-digit mobile number `01xxxxxxxxx`, empty when
  /// no session.
  final String mobile;

  /// True when the user has a locally-persisted subscription session.
  /// The router uses this to gate Home.
  final bool isSubscribed;

  /// Epoch millis of the last successful verify.
  final int lastVerifiedAtMs;
}

final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, SubscriptionState>(
  SubscriptionController.new,
);

/// Bangladesh mobile-number validators shared by both auth screens.
class MobileValidation {
  MobileValidation._();

  /// All-BD 11-digit mobile: `01[3-9]xxxxxxxx`.
  static final RegExp _allBd = RegExp(r'^01[3-9][0-9]{8}$');

  /// Robi / Cirkle only: `018` or `016` prefix. Matches the bdapps
  /// docs (018 Robi, 016 Cirkle) and the marketing screen copy.
  static final RegExp _robiCirkle = RegExp(r'^01(8|6)[0-9]{8}$');

  /// Returns `null` if [raw] is a valid Robi/Cirkle 11-digit number;
  /// otherwise a human-readable error message.
  static String? validateRobiCirkle(String raw) {
    final digits = _digits(raw);
    if (digits.isEmpty) return 'Enter your mobile number';
    if (digits.length != 11) {
      return 'Number must be 11 digits (01XXXXXXXXX)';
    }
    if (!_allBd.hasMatch(digits)) {
      return 'Enter a valid Bangladeshi mobile number';
    }
    if (!_robiCirkle.hasMatch(digits)) {
      return 'Only Robi (018) or Cirkle (016) numbers are supported';
    }
    return null;
  }

  /// Strips everything except digits.
  static String _digits(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'\D'), '');
}

/// Developer-bypass key. Typing exactly 11 zeros on either auth
/// screen bypasses bdapps entirely and grants the session directly —
/// keeps you unblocked while iterating on app features.
const String kDevBypassMobile = '00000000000';
