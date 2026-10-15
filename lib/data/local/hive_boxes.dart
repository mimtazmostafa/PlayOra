/// Single source of truth for Hive box names.
class HiveBoxes {
  HiveBoxes._();

  static const String appSettings = 'app_settings';
  static const String userProfile = 'user_profile';

  /// Key inside [userProfile] holding the player's display name.
  static const String profileKey = 'display_name';
  static const String gameLibrary = 'game_library';
  static const String rewards = 'rewards';

  /// Stores the last 5 search queries as a `List<String>` under [_key].
  static const String recentSearches = 'recent_searches';

  /// Key inside [recentSearches] holding the ordered query list.
  static const String recentSearchesKey = 'queries';

  /// Stores the set of favorited game ids as a `List<String>` under [_key].
  static const String favorites = 'favorites';

  /// Key inside [favorites] holding the favorited game ids.
  static const String favoritesKey = 'ids';

  /// Stores the user's current play-streak state (count + last day).
  static const String streak = 'streak';

  /// Key inside [streak] holding the snapshot map.
  static const String streakKey = 'snapshot';

  /// Stores per-day daily-challenge completion records, keyed by
  /// `YYYY-MM-DD` (one entry per day the user attempted).
  static const String dailyChallenge = 'daily_challenge';

  /// Stores the player's unlocked achievements as
  /// `{ achievementId: isoTimestamp }` under [unlockedKey].
  static const String achievements = 'achievements';

  /// Key inside [achievements] holding the unlock map.
  static const String unlockedKey = 'unlocked';

  /// Stores per-game play history as
  /// `{ gameId: isoTimestamp }` (last-played) under [playHistoryKey].
  static const String playHistory = 'play_history';

  /// Key inside [playHistory] holding the play map.
  static const String playHistoryKey = 'last_played';

  /// Stores per-game unlocked-level map as
  /// `{ gameId: <int highestUnlocked> }` under [levelProgressKey].
  static const String levelProgress = 'level_progress';

  /// Key inside [levelProgress] holding the per-game map.
  static const String levelProgressKey = 'progress';

  /// Stores the bdapps subscription session: subscriberId,
  /// isSubscribed flag, and last-verified timestamp. Persisted
  /// across cold starts so the user only re-auths after logout.
  static const String subscription = 'subscription';

  /// Key inside [subscription] holding the subscriber id
  /// (`tel:88xxxxxxxxxx`).
  static const String subscriberIdKey = 'subscriber_id';

  /// Key inside [subscription] holding the subscribed flag.
  static const String isSubscribedKey = 'is_subscribed';

  /// Key inside [subscription] holding the last-verified epoch millis.
  static const String lastVerifiedKey = 'last_verified_ms';

  /// Key inside [subscription] holding the logout-safe history of
  /// numbers that previously completed Subscribe on this device.
  /// Stored as a JSON-encoded `List<{mobile, subscriberId,
  /// lastVerifiedAtMs}>`. Survives `clearSession()` (logout) so the
  /// user can re-enter the same number on the Login screen even when
  /// the upstream BDApps `getStatus` endpoint mis-reports their
  /// subscription.
  static const String subscribedMobileHistoryKey =
      'subscribed_mobile_history';
}
