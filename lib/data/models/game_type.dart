/// How the game is rendered at runtime.
enum GameType {
  /// Built with native Flutter widgets — `entryPoint` resolves to a route.
  nativeFlutter,

  /// Loaded inside a WebView — `entryPoint` resolves to an asset path or URL.
  webview;

  String get wire => name;

  static GameType fromWire(String? raw) {
    for (final t in GameType.values) {
      if (t.name == raw) return t;
    }
    return GameType.nativeFlutter;
  }
}