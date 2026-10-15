/// Random / seeding utilities shared across mini-games.
///
/// Currently houses [dailySeedFor] which produces a stable per-day seed
/// so daily-challenge players see the same puzzle / spawn sequence on
/// the same UTC date across devices.
library;

/// Returns a stable 32-bit seed derived from today's UTC date and
/// the given [gameId] slug. Every call from any device on the same
/// date for the same game returns the same value; the value flips
/// at UTC midnight.
///
/// Pass a distinct slug per mini-game (e.g. `'fruit-slice'`,
/// `'tic-tac-toe'`, `'fruit-merge'`).
int dailySeedFor(String gameId) {
  final now = DateTime.now().toUtc();
  return '$now-${now.month}-${now.day}-$gameId'.hashCode;
}
