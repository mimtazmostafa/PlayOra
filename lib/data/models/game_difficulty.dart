enum GameDifficulty {
  easy,
  medium,
  hard;

  String get wire => name;

  static GameDifficulty fromWire(String? raw) {
    for (final d in GameDifficulty.values) {
      if (d.name == raw) return d;
    }
    return GameDifficulty.easy;
  }
}