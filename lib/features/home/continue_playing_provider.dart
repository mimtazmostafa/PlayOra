import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/game_model.dart';
import '../games/games_providers.dart';
import '../profile/played_games_controller.dart';

/// Max number of tiles to show on the Home "Continue Playing" row.
///
/// Picked so the row fits cleanly on a 360dp-wide phone (5 tiles
/// at ~140dp wide + gaps + side padding) without horizontal
/// scroll fatigue.
const int kContinuePlayingLimit = 5;

/// Reactive stream of "continue playing" games derived from the
/// [PlayedGamesController] history + the catalog provider.
///
/// Returns the most-recent [kContinuePlayingLimit] games the player
/// has launched, in last-played order. Titles that have since been
/// removed from the catalog are silently dropped (so renaming /
/// deletion in the seed JSON doesn't leave a broken tile).
class ContinuePlayingNotifier
    extends AsyncNotifier<List<Game>> {
  @override
  Future<List<Game>> build() async {
    // Watch the history map and the full catalog. Either changing
    // re-runs the derivation below.
    final history = ref.watch(playedGamesControllerProvider);
    final games = await ref.watch(gamesProvider.future);
    final byId = <String, Game>{
      for (final g in games) g.id: g,
    };
    // Sort by lastPlayedAt descending, drop unknown ids, cap.
    final entries = history.entries
        .where((e) => byId.containsKey(e.key))
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(kContinuePlayingLimit)
        .map((e) => byId[e.key]!)
        .toList(growable: false);
  }
}

final continuePlayingProvider =
    AsyncNotifierProvider<ContinuePlayingNotifier, List<Game>>(
  ContinuePlayingNotifier.new,
);
