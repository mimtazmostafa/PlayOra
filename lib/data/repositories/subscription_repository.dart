import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../local/hive_boxes.dart';

/// Defensive regex used by both [HiveSubscriptionRepository] and
/// [InMemorySubscriptionRepository] when reconstructing the
/// 11-digit mobile from a stored subscriber id.
///
/// Mirrors the canonical Robi/Cirkle spec used by the rest of the
/// auth flow. Keeping it local to this file avoids a dependency
/// cycle with `features/auth/auth_controller.dart`.
final RegExp _validRobiCirkleMobile = RegExp(r'^01(8|6)[0-9]{8}$');

/// Canonical carrier-side subscriber id shape: `tel:88` followed by
/// the same 11 digits that the mobile field carries (with the
/// leading `0`).
final RegExp _validSubscriberId = RegExp(r'^tel:88(01(8|6)[0-9]{8})$');

/// Sentinel values used by the in-app dev-bypass flow (the
/// `00000000000` mobile that grants a session without hitting
/// bdapps). These deliberately do NOT match the production regexes
/// above (they start with `00` instead of `018`/`016`), but the
/// auth controllers write them as-is for the dev loop. We special-
/// case them in [HiveSubscriptionRepository.setSession] /
/// [InMemorySubscriptionRepository.setSession] so the regex strip
/// does not silently corrupt the persisted session.
const String _devBypassMobile = '00000000000';
const String _devBypassSubscriberId = 'tel:880000000000';

/// Holds the bdapps subscription session that gates access to the
/// rest of the app. Persisted across cold starts so returning users
/// land straight on the home shell (Logout/Unsubscribe clear it).
///
/// Two implementations:
/// - [HiveSubscriptionRepository] — backed by Hive (production).
/// - [InMemorySubscriptionRepository] — for tests / previews.
///
/// On top of the active session, the repository also keeps a
/// logout-safe **history** of numbers that previously completed
/// Subscribe on this device. The Login screen falls back to the
/// history record when the upstream `check_subscription.php`
/// call mis-reports a REGISTERED user as UNREGISTERED (a known
/// BDApps-side `getStatus` issue).
abstract class SubscriptionRepository {
  /// Subscriber id in the bdapps `tel:88xxxxxxxxxx` format. Empty when
  /// no session is active.
  String subscriberId();

  /// The 11-digit Bangladeshi mobile number behind the subscriber id,
  /// normalised to `01xxxxxxxxx`. Empty when no session is active.
  String mobile();

  /// Whether the user currently has an active subscription session.
  /// Logout clears this without touching the carrier-side subscription;
  /// Unsubscribe clears it AND tells bdapps to cancel.
  bool isSubscribed();

  /// When `isSubscribed()` last flipped to true, in epoch millis.
  /// Used by the auth gate to decide whether to re-verify against the
  /// backend before letting the user in.
  int lastVerifiedAtMs();

  /// Persist a freshly-verified subscription. Also records the
  /// mobile/subscriberId in the logout-safe history so a later
  /// Logout → Login round-trip can still recognise the user when
  /// the upstream getStatus call is mis-reporting.
  Future<void> setSession({
    required String subscriberId,
    required String mobile,
    required bool isSubscribed,
  });

  /// Clear the active session without touching the carrier. Used by
  /// Logout and as a defensive reset when check-subscription returns
  /// not-subscribed. The logout-safe history survives this call so
  /// returning users can still be recognised on Login.
  Future<void> clearSession();

  /// Look up a previously-subscribed mobile in the logout-safe
  /// history. Returns `null` if this device has no record of the
  /// number having completed Subscribe.
  SubscriptionHistoryEntry? findHistoryForMobile(String mobile);

  /// Drop a single mobile from the history — called by the
  /// Unsubscribe flow so a user who cancels carrier-side is properly
  /// forgotten.
  Future<void> forgetMobile(String mobile);
}

/// Plain data carrier for a history record. Mirrors the JSON shape
/// persisted in Hive so callers don't need to know about the wire
/// format.
class SubscriptionHistoryEntry {
  const SubscriptionHistoryEntry({
    required this.mobile,
    required this.subscriberId,
    required this.lastVerifiedAtMs,
  });

  final String mobile;
  final String subscriberId;
  final int lastVerifiedAtMs;

  Map<String, dynamic> toJson() => {
        'mobile': mobile,
        'subscriberId': subscriberId,
        'lastVerifiedAtMs': lastVerifiedAtMs,
      };

  factory SubscriptionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistoryEntry(
      mobile: json['mobile']?.toString() ?? '',
      subscriberId: json['subscriberId']?.toString() ?? '',
      lastVerifiedAtMs: json['lastVerifiedAtMs'] is int
          ? json['lastVerifiedAtMs'] as int
          : 0,
    );
  }
}

class HiveSubscriptionRepository implements SubscriptionRepository {
  HiveSubscriptionRepository(this._box);

  /// Open the subscription box. Call once at startup (Hive must already
  /// be init'd via `HiveSetup.init`).
  static Future<HiveSubscriptionRepository> open() async {
    final box = await Hive.openBox<dynamic>(HiveBoxes.subscription);
    return HiveSubscriptionRepository(box);
  }

  final Box<dynamic> _box;

  @override
  String subscriberId() =>
      (_box.get(HiveBoxes.subscriberIdKey) as String?) ?? '';

  @override
  String mobile() {
    final subId = subscriberId();
    // Only reconstruct the 11-digit mobile when the stored
    // subscriber id matches the canonical `tel:88xxxxxxxxxx` shape
    // — i.e. the carrier-side id we generated ourselves when the
    // user completed Subscribe. A malformed stored value (from a
    // previous build that didn't validate) would otherwise produce
    // strings like `0801889780801` that look like a number but
    // aren't valid Robi/Cirkle.
    final match = _validSubscriberId.firstMatch(subId);
    if (match != null) return match.group(1)!;
    // Dev-bypass sentinel: the auth controllers write
    // `tel:880000000000` for the in-app dev loop. It deliberately
    // doesn't match the production regex (starts with `00`), so
    // reconstruct the bypass mobile explicitly so `mobile()`
    // returns `00000000000` instead of empty.
    if (subId == _devBypassSubscriberId) return _devBypassMobile;
    return '';
  }

  @override
  bool isSubscribed() => _box.get(HiveBoxes.isSubscribedKey) == true;

  @override
  int lastVerifiedAtMs() {
    final raw = _box.get(HiveBoxes.lastVerifiedKey);
    return raw is int ? raw : 0;
  }

  @override
  Future<void> setSession({
    required String subscriberId,
    required String mobile,
    required bool isSubscribed,
  }) async {
    // Refuse to write a malformed subscriber id / mobile pair.
    // The Login flow already enforces the Robi/Cirkle regex on
    // entry, but defence-in-depth here means a stray call (e.g.
    // from an older build) can't poison the persisted state.
    //
    // Special-case: the dev-bypass sentinel mobile
    // `00000000000` / `tel:880000000000` deliberately does NOT
    // match the production regexes (it starts with `00` not
    // `018`/`016`), but it's a valid in-app session marker. We
    // pass it through unchanged so the dev loop round-trips
    // cleanly without forcing the user to a state where
    // `mobile()` returns '' and they're stuck subscribed with
    // no mobile to verify against. History records stay empty
    // for the bypass because the `_recordHistory` guard at
    // the bottom of this method still gates on
    // `mobile.isNotEmpty && subscriberId.isNotEmpty`.
    if (subscriberId.isNotEmpty &&
        subscriberId != _devBypassSubscriberId &&
        !_validSubscriberId.hasMatch(subscriberId)) {
      // Strip the malformed id and keep the rest; the resulting
      // mobile() will return '' because the regex won't match.
      subscriberId = '';
    }
    if (mobile.isNotEmpty &&
        mobile != _devBypassMobile &&
        !_validRobiCirkleMobile.hasMatch(mobile)) {
      mobile = '';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _box.putAll({
      HiveBoxes.subscriberIdKey: subscriberId,
      HiveBoxes.isSubscribedKey: isSubscribed,
      HiveBoxes.lastVerifiedKey: now,
    });
    // Sanity-check: store `mobile` for offline display; we don't use
    // it as the canonical id.
    if (mobile.isNotEmpty) {
      await _box.put('mobile', mobile);
    }
    if (mobile.isNotEmpty && subscriberId.isNotEmpty) {
      await _recordHistory(
        mobile: mobile,
        subscriberId: subscriberId,
        lastVerifiedAtMs: now,
      );
    }
  }

  @override
  Future<void> clearSession() async {
    // Wipe only the active-session keys. The logout-safe history
    // lives under its own key and survives Logout so a returning
    // user on the same device can be recognised on Login.
    await _box.delete(HiveBoxes.subscriberIdKey);
    await _box.delete(HiveBoxes.isSubscribedKey);
    await _box.delete(HiveBoxes.lastVerifiedKey);
    await _box.delete('mobile');
  }

  @override
  SubscriptionHistoryEntry? findHistoryForMobile(String mobile) {
    final list = _readHistory();
    for (final entry in list) {
      if (entry.mobile == mobile) return entry;
    }
    return null;
  }

  @override
  Future<void> forgetMobile(String mobile) async {
    final list = _readHistory();
    final filtered = list.where((e) => e.mobile != mobile).toList();
    if (filtered.length == list.length) return; // no-op
    await _writeHistory(filtered);
  }

  // ─────────────────────────────────────────────────────────────
  // History I/O — JSON-encoded List<SubscriptionHistoryEntry>
  // stored under a single key. Compact, easy to migrate, and
  // tolerates garbage by returning an empty list.
  // ─────────────────────────────────────────────────────────────

  List<SubscriptionHistoryEntry> _readHistory() {
    final raw = _box.get(HiveBoxes.subscribedMobileHistoryKey);
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SubscriptionHistoryEntry.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeHistory(
    List<SubscriptionHistoryEntry> entries,
  ) async {
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _box.put(HiveBoxes.subscribedMobileHistoryKey, encoded);
  }

  Future<void> _recordHistory({
    required String mobile,
    required String subscriberId,
    required int lastVerifiedAtMs,
  }) async {
    final list = List<SubscriptionHistoryEntry>.from(_readHistory());
    final idx = list.indexWhere((e) => e.mobile == mobile);
    final entry = SubscriptionHistoryEntry(
      mobile: mobile,
      subscriberId: subscriberId,
      lastVerifiedAtMs: lastVerifiedAtMs,
    );
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await _writeHistory(list);
  }
}

class InMemorySubscriptionRepository implements SubscriptionRepository {
  String _subscriberId = '';
  String _mobile = '';
  bool _isSubscribed = false;
  int _lastVerifiedAtMs = 0;
  final List<SubscriptionHistoryEntry> _history = [];

  /// Test helper — pre-populate a session.
  void seed({
    String subscriberId = '',
    String mobile = '',
    bool isSubscribed = false,
    int lastVerifiedAtMs = 0,
  }) {
    _subscriberId = subscriberId;
    _mobile = mobile;
    _isSubscribed = isSubscribed;
    _lastVerifiedAtMs = lastVerifiedAtMs;
  }

  /// Test helper — pre-populate history.
  void seedHistory(Iterable<SubscriptionHistoryEntry> entries) {
    _history
      ..clear()
      ..addAll(entries);
  }

  /// Test helper — read the in-memory history.
  List<SubscriptionHistoryEntry> readHistory() =>
      List.unmodifiable(_history);

  @override
  String subscriberId() => _subscriberId;

  @override
  String mobile() => _mobile;

  @override
  bool isSubscribed() => _isSubscribed;

  @override
  int lastVerifiedAtMs() => _lastVerifiedAtMs;

  @override
  Future<void> setSession({
    required String subscriberId,
    required String mobile,
    required bool isSubscribed,
  }) async {
    // Refuse to store a malformed subscriber id / mobile pair —
    // see the Hive impl for the rationale. The dev-bypass
    // sentinel is allowed through unchanged (mirrors the Hive
    // behaviour).
    if (subscriberId.isNotEmpty &&
        subscriberId != _devBypassSubscriberId &&
        !_validSubscriberId.hasMatch(subscriberId)) {
      subscriberId = '';
    }
    if (mobile.isNotEmpty &&
        mobile != _devBypassMobile &&
        !_validRobiCirkleMobile.hasMatch(mobile)) {
      mobile = '';
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _subscriberId = subscriberId;
    _mobile = mobile;
    _isSubscribed = isSubscribed;
    _lastVerifiedAtMs = now;
    if (mobile.isNotEmpty && subscriberId.isNotEmpty) {
      final idx = _history.indexWhere((e) => e.mobile == mobile);
      final entry = SubscriptionHistoryEntry(
        mobile: mobile,
        subscriberId: subscriberId,
        lastVerifiedAtMs: now,
      );
      if (idx >= 0) {
        _history[idx] = entry;
      } else {
        _history.add(entry);
      }
    }
  }

  @override
  Future<void> clearSession() async {
    _subscriberId = '';
    _mobile = '';
    _isSubscribed = false;
    _lastVerifiedAtMs = 0;
    // History survives.
  }

  @override
  SubscriptionHistoryEntry? findHistoryForMobile(String mobile) {
    for (final entry in _history) {
      if (entry.mobile == mobile) return entry;
    }
    return null;
  }

  @override
  Future<void> forgetMobile(String mobile) async {
    _history.removeWhere((e) => e.mobile == mobile);
  }
}
