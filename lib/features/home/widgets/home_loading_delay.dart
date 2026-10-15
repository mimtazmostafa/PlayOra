/// Simulated loading delay for the home screen.
///
/// The real catalog is local JSON, so this exists only to make the loading
/// state visible — and to let tests exercise it without flakiness.
class HomeLoadingDelay {
  const HomeLoadingDelay({this.duration = const Duration(milliseconds: 450)});

  final Duration duration;

  Future<void> wait() => Future<void>.delayed(duration);
}
