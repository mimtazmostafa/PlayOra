/// Top-level game groupings shown in the Categories tab.
///
/// Stored as kebab-case strings in the JSON seed / future API responses.
enum GameCategory {
  puzzle,
  arcade,
  brain,
  sports,
  board,
  /// Word games (Bangla Word Connect, Bangla Word Search). Added so
  /// the redesigned Home / Games screens can surface a fifth category
  /// tile matching the reference design without overloading "Puzzle".
  word,
  action,
  racing,
  strategy,
  educational;

  /// Stable wire format. Keep in sync with the values in
  /// `assets/data/games_seed.json` and the API contract when introduced.
  String get wire => name;

  static GameCategory fromWire(String? raw) {
    for (final c in GameCategory.values) {
      if (c.name == raw) return c;
    }
    // Unknown string → fall back to the most generic category so the UI
    // still has a tile to render. Refusing to throw keeps the catalog
    // resilient to backend rollouts.
    return GameCategory.arcade;
  }
}