import 'package:characters/characters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/profile_repository.dart';

/// Provider for the underlying [ProfileRepository]. Overridden in
/// `main.dart` with the Hive-backed implementation; tests override
/// with [InMemoryProfileRepository].
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  throw UnimplementedError(
    'profileRepositoryProvider must be overridden in ProviderScope',
  );
});

/// Default name shown when the player hasn't picked one yet.
const String kDefaultPlayerName = 'Player';

/// Reactive view of the player's display name.
///
/// Kept intentionally simple — no validation library, no nickname
/// uniqueness check. The on-screen editor trims / clamps the input
/// length before calling [setName]; the controller just persists
/// whatever it gets.
class ProfileController extends Notifier<String> {
  @override
  String build() {
    final repo = ref.read(profileRepositoryProvider);
    final stored = repo.getDisplayName().trim();
    return stored.isEmpty ? kDefaultPlayerName : stored;
  }

  /// Persist [name] as the new display name. Empty / whitespace-only
  /// inputs fall back to [kDefaultPlayerName] so the avatar initials
  /// never render blank.
  Future<void> setName(String name) async {
    final trimmed = name.trim();
    final next = trimmed.isEmpty ? kDefaultPlayerName : trimmed;
    await ref.read(profileRepositoryProvider).setDisplayName(next);
    state = next;
  }

  /// Two-letter initials derived from [name]. Used by the avatar when
  /// no profile picture is configured.
  ///
  /// - "Player" → "P"
  /// - "Sadman Ahmed" → "SA"
  /// - "" (theoretical) → "?"
  String get initials {
    final parts = state
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

final profileControllerProvider =
    NotifierProvider<ProfileController, String>(ProfileController.new);
