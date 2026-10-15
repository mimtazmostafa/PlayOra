import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bottom_nav_shell.dart';

/// Wraps any child so that, while it is on screen, the bottom
/// navigation bar slides off-screen.
///
/// Why is this needed even though the game player route lives *above*
/// the shell in the navigator stack?
///
///   * When a game is pushed, the shell really does disappear — but
///     the slide-out transition fires after the push has already
///     committed, so the user sees the bar briefly on top of the game
///     for a frame. Wrapping the player screen gives us an explicit
///     `initState` hook to flip the flag *before* the first frame.
///   * Future in-shell screens (an embedded mini-game preview, a full
///     game list with a quick-play tile, etc.) can drop the same
///     wrapper to get identical behavior.
class HideBottomNav extends ConsumerStatefulWidget {
  const HideBottomNav({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HideBottomNav> createState() => _HideBottomNavState();
}

class _HideBottomNavState extends ConsumerState<HideBottomNav> {
  /// Captured in [initState] so [dispose] can flip it back without
  /// touching `ref` (Riverpod throws on ref reads after dispose).
  late final StateController<bool> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(showBottomNavProvider.notifier);
    // Flip the flag synchronously so the bottom bar starts its slide
    // on the very next frame — no visible "frame of bar over game".
    Future.microtask(() {
      if (!mounted) return;
      _notifier.state = false;
    });
  }

  @override
  void dispose() {
    // Restore the flag when the wrapped screen leaves the tree so
    // popping back to the dashboard brings the bar back smoothly.
    // We must NOT touch `ref` here — the ConsumerStatefulElement is
    // already disposed at this point and Riverpod throws
    // "Cannot use ref after the widget was disposed". We use the
    // notifier captured in initState instead.
    final n = _notifier;
    Future.microtask(() {
      n.state = true;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
