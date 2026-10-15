import '../../data/models/game_model.dart';

/// Sort order for the Category Detail screen.
///
/// The catalog doesn't carry play-count or release-date metadata yet, so the
/// "Popular" and "New" options are derived from seed-file order (assumed
/// curated popularity/release rank). "Quick Play" filters by
/// [Game.avgSessionMinutes]. All three are pure — no network or random state.
enum CategorySort {
  /// First-to-last in the seed = assumed most popular first.
  popular('Popular'),

  /// Reverse of the seed = assumed newest first. Easy to flip later when real
  /// release-date metadata arrives.
  newest('New'),

  /// Shortest session first. Always re-sorted regardless of seed order so the
  /// label matches what the user sees.
  quickPlay('Quick Play <2 min');

  const CategorySort(this.label);

  /// Text shown in the dropdown.
  final String label;
}

/// Apply [sort] to [games]. Pure — never mutates the input list.
List<Game> sortGames(List<Game> games, CategorySort sort) {
  switch (sort) {
    case CategorySort.popular:
      return List<Game>.unmodifiable(games);
    case CategorySort.newest:
      return List<Game>.unmodifiable(games.reversed);
    case CategorySort.quickPlay:
      // Filter then sort ascending by session length. Sessions of 0 or 1
      // minutes qualify as "quick play" (<2 min).
      final quick = games.where((g) => g.avgSessionMinutes < 2).toList()
        ..sort((a, b) => a.avgSessionMinutes.compareTo(b.avgSessionMinutes));
      return List<Game>.unmodifiable(quick);
  }
}
