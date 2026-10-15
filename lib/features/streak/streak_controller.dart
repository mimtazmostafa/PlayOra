import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/streak_repository.dart';
import 'streak_model.dart';

/// Reactive play-streak state + persistence boundary.
///
/// Owns a [StreakSnapshot] in memory and writes every change to the
/// repository. Exposes [recordSession] for post-game hooks. When the
/// count grows (i.e. today extends an existing streak), the new
/// count is emitted on [streakUpStream] so the UI can celebrate.
class StreakController extends Notifier<StreakSnapshot> {
  late StreakRepository _repo;
  final StreakMath _math = const StreakMath();
  final StreamController<int> _streakUpController =
      StreamController<int>.broadcast();

  /// One event for each new streak high (e.g. `2 → 3`).
  /// Listeners can render a small flame burst.
  Stream<int> get streakUpStream => _streakUpController.stream;

  @override
  StreakSnapshot build() {
    _repo = ref.read(streakRepositoryProvider);
    ref.onDispose(() {
      if (!_streakUpController.isClosed) {
        _streakUpController.close();
      }
    });
    return _repo.load();
  }

  /// Records a play session on [now] (defaults to [DateTime.now]).
  /// Returns the snapshot after applying the day-gating rules.
  ///
  /// When [notify] is true and the count grows beyond 1 (i.e. an
  /// existing streak was extended), the new count is emitted on
  /// [streakUpStream]. A reset to 1 does *not* emit.
  Future<StreakSnapshot> recordSession({
    DateTime? now,
    bool notify = true,
  }) async {
    final current = state;
    final at = now ?? DateTime.now();
    final next = _math.recordSession(current, at);

    if (next == current) {
      return current;
    }

    state = next;
    await _repo.save(next);

    if (notify && next.count > current.count && next.count > 1) {
      _streakUpController.add(next.count);
    }
    return next;
  }

  /// Test-only: drop the snapshot back to empty.
  Future<void> reset() async {
    state = StreakSnapshot.empty;
    await _repo.save(StreakSnapshot.empty);
  }
}

/// Provider for the underlying [StreakRepository]. Overridden in
/// `main.dart` with the Hive-backed implementation; tests override
/// with [InMemoryStreakRepository].
final streakRepositoryProvider = Provider<StreakRepository>((ref) {
  throw UnimplementedError(
    'streakRepositoryProvider must be overridden in ProviderScope',
  );
});

final streakControllerProvider =
    NotifierProvider<StreakController, StreakSnapshot>(
  StreakController.new,
);

/// Convenience stream provider that surfaces the latest streak-up
/// event to overlays / global listeners.
final streakUpStreamProvider = StreamProvider<int>((ref) {
  final controller = ref.watch(streakControllerProvider.notifier);
  return controller.streakUpStream;
});