import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_model.dart';
import '../games/games_providers.dart';

/// Duration buckets surfaced by the "Quick Play" pill strip.
///
/// The bucket names map directly to the pill labels the home screen
/// renders. `surprise` deliberately ignores `avgSessionMinutes` so the
/// user gets a true random pick.
enum QuickPlayBucket {
  twoMinute(label: '2 MIN', emoji: '🧠', maxMinutes: 3),
  threeMinute(label: '3 MIN', emoji: '🎯', maxMinutes: 4),
  surprise(label: 'Surprise Me', emoji: '🎲', maxMinutes: null);

  const QuickPlayBucket({
    required this.label,
    required this.emoji,
    required this.maxMinutes,
  });

  /// Pill label.
  final String label;

  /// Emoji prefix used on the pill.
  final String emoji;

  /// Inclusive upper-bound on `Game.avgSessionMinutes`. `null` means
  /// no bound (surprise mode).
  final int? maxMinutes;
}

/// Reactive picker for the Quick Play strip. Returns a [Game] that
/// matches the requested [QuickPlayBucket] — or `null` when no offline
/// game in the catalog satisfies the constraint.
///
/// The picker is seeded by *date + bucket* so:
///   * successive taps on the same pill today return different games
///     (RNG walks across the list)
///   * the user gets a stable pick if they back out and re-enter the
///     screen on the same day for the same bucket
class QuickPlayNotifier extends AsyncNotifier<Game?> {
  static final Random _rng = Random();

  @override
  Future<Game?> build() async {
    // No-op future — actual pick happens via [pick]. We expose an
    // AsyncNotifier so the UI gets `loading` / `data` / `error` for
    // free without us re-implementing state plumbing.
    return null;
  }

  /// Pick a random offline game for [bucket]. Returns the chosen
  /// game, or `null` if the catalog has no candidates.
  Future<Game?> pick(QuickPlayBucket bucket) async {
    final games = await ref.read(gamesProvider.future);
    // Only offline-available games qualify — Quick Play is for
    // instant fun without network. Exclude coming-soon placeholders
    // because they can't actually launch.
    final candidates = games.where((g) {
      if (!g.isOfflineAvailable) return false;
      if (g.comingSoon) return false;
      if (bucket.maxMinutes == null) return true;
      return g.avgSessionMinutes <= bucket.maxMinutes!;
    }).toList(growable: false);

    if (candidates.isEmpty) {
      state = const AsyncValue.data(null);
      return null;
    }
    final picked = candidates[_rng.nextInt(candidates.length)];
    state = AsyncValue.data(picked);
    return picked;
  }
}

final quickPlayProvider =
    AsyncNotifierProvider<QuickPlayNotifier, Game?>(QuickPlayNotifier.new);
