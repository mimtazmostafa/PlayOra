import 'package:flutter/widgets.dart';

import 'ludo_board.dart';
import 'ludo_model.dart';

/// A tweened location for a single token. While a move is in flight
/// the painter uses [center] + [phase] instead of the static
/// `state`-derived offset.
///
/// - [center]: where to draw the disc (already eased over the
///   intermediate cells of the move).
/// - [phase]: 0..1 of move progress — drives a subtle scale pulse
///   so the player can see the token "lifting off" + "landing".
class LudoTokenTween {
  const LudoTokenTween({required this.center, required this.phase});
  final Offset center;
  final double phase;
}

/// Pure helpers that translate a [LudoPosition] into a 15x15 grid
/// (row, col) so the [LudoMotionController] can interpolate between
/// the old and new cells during a move. Mirrors the painter logic in
/// [LudoBoardPainter] so the trail exactly matches what the renderer
/// draws.
class LudoMotion {
  LudoMotion._();

  /// Returns the (row, col) of [pos] on the 15x15 board for
  /// [player]. Returns null for yard home positions because those
  /// are not on the main loop and the trail resolves yard exits
  /// separately.
  static (int row, int col)? cellFor(LudoPlayer player, LudoPosition pos) {
    if (pos is LudoPositionPath) {
      if (pos.pathIndex < 0 ||
          pos.pathIndex >= LudoBoardPainter.mainPath.length) {
        return null;
      }
      return LudoBoardPainter.mainPath[pos.pathIndex];
    }
    if (pos is LudoPositionStretch) {
      final layout = LudoBoardPainter.stretchLayout[player];
      if (layout == null || pos.stretchIndex >= layout.length) return null;
      return layout[pos.stretchIndex];
    }
    if (pos is LudoPositionFinished) {
      // Finished tokens cluster around the center for each seat.
      final dx = player.seat.isEven ? 1 : -1;
      final dy = player.seat < 2 ? 1 : -1;
      return (7 + dy, 7 + dx);
    }
    if (pos is LudoPositionHome) {
      return _yardCell(player, pos.yardSlot);
    }
    return null;
  }

  /// Same-yard center used for both the spawn point of a yard exit
  /// and the destination of a captured token returning home.
  static (int row, int col) _yardCell(LudoPlayer player, int slot) {
    final colOffset = (slot % 2) * 2; // 0 or 2
    final rowOffset = (slot ~/ 2) * 2;
    return switch (player) {
      LudoPlayer.red => (1 + rowOffset, 1 + colOffset),
      LudoPlayer.green => (1 + rowOffset, 10 + colOffset),
      LudoPlayer.yellow => (10 + rowOffset, 10 + colOffset),
      LudoPlayer.blue => (10 + rowOffset, 1 + colOffset),
    };
  }

  /// Returns a list of (row, col) cells that a token will pass
  /// through during its move. The list includes both endpoints; the
  /// motion controller walks the intermediate points to keep the
  /// tween linear-per-cell rather than curving.
  ///
  /// For yard exits the trail is just [yardSlot] -> [startCell].
  /// For captures (opponent sent home) the trail is
  /// [capturedCell] -> [opponentYardSlot].
  static List<(int row, int col)> trail({
    required LudoPlayer movingPlayer,
    required LudoPosition oldPos,
    required LudoPosition newPos,
    LudoPlayer? captureOpponent,
  }) {
    final start = cellFor(movingPlayer, oldPos);
    final end = cellFor(movingPlayer, newPos);
    if (start == null || end == null) {
      // Either end was off-board — for captures of finished tokens
      // we approximate with a short yard hop instead.
      if (captureOpponent != null) {
        return const [];
      }
      return const [];
    }
    // Path-to-path: walk the main loop one cell at a time so the
    // token visibly visits each intermediate square.
    if (oldPos is LudoPositionPath && newPos is LudoPositionPath) {
      return _walkPath(oldPos.pathIndex, newPos.pathIndex);
    }
    // Path -> stretch (diversion): just jump across to the
    // stretch cell; no visible per-step walk because the transition
    // is a single visual hop in standard Ludo.
    // Stretch stretch-stretch and stretch->finished are similar.
    return <(int, int)>[start, end];
  }

  /// Captured opponent token's trail: from the cell where it was
  /// captured back to its own yard center.
  static List<(int row, int col)> captureTrail({
    required LudoPlayer opponent,
    required int opponentTokenIndex,
    required (int row, int col) capturedAt,
  }) {
    final yard = _yardCell(opponent, opponentTokenIndex);
    return <(int, int)>[capturedAt, yard];
  }

  static List<(int row, int col)> _walkPath(int from, int to) {
    if (from == to) return <(int, int)>[LudoBoardPainter.mainPath[from]];
    final out = <(int, int)>[];
    var cur = from;
    // The 52-cell loop is a forward-only loop in standard play; the
    // controller should never ask for backward steps here. If a
    // caller hands us a backward move we fall back to a teleport so
    // we never animate the token travelling the wrong way around
    // the loop.
    final forward = (to - from + kMainPathLength) % kMainPathLength;
    if (forward > 6) {
      // Implausibly large forward distance — defensive fallback.
      return <(int, int)>[LudoBoardPainter.mainPath[from]];
    }
    for (var step = 0; step <= forward; step++) {
      out.add(LudoBoardPainter.mainPath[cur]);
      cur = (cur + 1) % kMainPathLength;
    }
    return out;
  }
}

/// Drives the per-move token tweens for the Ludo board.
///
/// The controller emits state transitions; this widget-level helper
/// watches those, computes the trail of intermediate cells for each
/// moving token, and produces a `Map<(LudoPlayer, tokenIndex),
/// LudoTokenTween>` that the [LudoBoardPainter] consults instead of
/// the static `state`-driven offsets.
///
/// Animation budget: ~80 ms per cell, capped at 480 ms total.
class LudoMotionController extends ChangeNotifier {
  LudoMotionController({required this.vsync});

  final TickerProvider vsync;

  /// The current tween overrides for the painter. Empty when no
  /// move is in flight.
  final Map<(LudoPlayer, int), LudoTokenTween> _overrides = {};

  AnimationController? _ac;
  List<List<(int row, int col)>> _trailsByToken = const [];
  List<(LudoPlayer, int)> _keysByTrail = const [];
  int _trailCount = 0;

  LudoState? _prev;
  LudoState? _next;
  Duration _moveDuration = Duration.zero;

  /// Whether a move is currently animating.
  bool get isAnimating => _ac?.isAnimating ?? false;

  /// Returns the tweened center for the given token if it is
  /// currently animating, or null if the token should fall back to
  /// its static state-derived position.
  LudoTokenTween? tweened(LudoPlayer player, int tokenIndex) =>
      _overrides[(player, tokenIndex)];

  /// Starts a move animation if the previous->next transition
  /// involves any token moving. Safe to call with state transitions
  /// that involve no token changes (turn advance, dice flip, etc.)
  /// — those are a no-op.
  void start(LudoState prev, LudoState next) {
    _prev = prev;
    _next = next;
    if (identical(prev, next)) return;
    if (_isSameTokenSet(prev, next) && _captures(prev, next).isEmpty) {
      return;
    }
    _scheduleAnimation();
  }

  bool _isSameTokenSet(LudoState a, LudoState b) {
    for (var s = 0; s < a.players.length; s++) {
      for (var i = 0; i < a.players[s].tokens.length; i++) {
        if (a.players[s].tokens[i] != b.players[s].tokens[i]) return false;
      }
    }
    return true;
  }

  /// Returns the captured opponent token snapshots between
  /// [prev] and [next] by diffing token positions whose PREVIOUS
  /// location was path and whose NEW location is home.
  List<({LudoPlayer opponent, int tokenIndex, (int, int) capturedAt})>
      _captures(LudoState prev, LudoState next) {
    final out = <({LudoPlayer opponent, int tokenIndex, (int, int) capturedAt})>[];
    for (final p in LudoPlayer.values) {
      final a = prev.players[p.seat].tokens;
      final b = next.players[p.seat].tokens;
      for (var i = 0; i < a.length; i++) {
        final oldP = a[i];
        if (oldP is! LudoPositionPath) continue;
        if (b[i] is LudoPositionHome) {
          final captured = LudoMotion.cellFor(p, oldP);
          if (captured != null) {
            out.add((
              opponent: p,
              tokenIndex: i,
              capturedAt: captured,
            ));
          }
        }
      }
    }
    return out;
  }

  void _scheduleAnimation() {
    final prev = _prev!;
    final next = _next!;
    _ac?.stop();
    _ac?.dispose();
    _overrides.clear();

    // Build the list of trails — one per moving token, plus one per
    // captured opponent token.
    final trails = <List<(int, int)>>[];
    final keys = <(LudoPlayer, int)>[];
    for (final p in LudoPlayer.values) {
      final a = prev.players[p.seat].tokens;
      final b = next.players[p.seat].tokens;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          final t = LudoMotion.trail(
            movingPlayer: p,
            oldPos: a[i],
            newPos: b[i],
          );
          if (t.isNotEmpty) {
            trails.add(t);
            keys.add((p, i));
          }
        }
      }
    }
    for (final cap in _captures(prev, next)) {
      final t = LudoMotion.captureTrail(
        opponent: cap.opponent,
        opponentTokenIndex: cap.tokenIndex,
        capturedAt: cap.capturedAt,
      );
      if (t.isNotEmpty) {
        trails.add(t);
        keys.add((cap.opponent, cap.tokenIndex));
      }
    }
    if (trails.isEmpty) return;

    // Per-cell duration, capped so a max-step 6 doesn't take 480ms.
    final maxCells = trails.fold<int>(0, (m, t) => t.length > m ? t.length : m);
    final perCellMs = 80;
    final requested = maxCells * perCellMs;
    final totalMs = requested.clamp(80, 480);
    _moveDuration = Duration(milliseconds: totalMs);
    _trailsByToken = trails;
    _keysByTrail = keys;
    _trailCount = trails.length;
    _ac = AnimationController(vsync: vsync, duration: _moveDuration)
      ..addListener(_onTick)
      ..forward();
    _onTick();
  }

  void _onTick() {
    if (_ac == null || _prev == null || _next == null) return;
    final raw = _ac!.value;
    final t = Curves.easeOutCubic.transform(raw);
    // Find the global progress across all trails (we drive a single
    // AnimationController and split t across trails by length, so a
    // short trail finishes partway through the animation).
    _overrides.clear();
    for (var idx = 0; idx < _trailCount; idx++) {
      final trail = _trailsByToken[idx];
      final key = _keysByTrail[idx];
      // Each trail runs in the [idx / N, (idx + 1) / N] slice of
      // total time. We stagger starts slightly so multiple moving
      // tokens don't perfectly overlap (visual depth).
      final startFrac = (idx / _trailCount).clamp(0.0, 1.0);
      final endFrac = ((idx + 1) / _trailCount).clamp(startFrac + 0.001, 1.0);
      final localT = ((t - startFrac) / (endFrac - startFrac)).clamp(0.0, 1.0);
      final pos = _interpolateTrail(trail, localT);
      _overrides[key] = LudoTokenTween(center: pos, phase: localT);
    }
    notifyListeners();
  }

  Offset _interpolateTrail(List<(int row, int col)> trail, double t) {
    if (trail.length == 1) {
      final c = trail.first;
      return Offset(c.$2.toDouble(), c.$1.toDouble());
    }
    if (t <= 0) {
      final c = trail.first;
      return Offset(c.$2.toDouble(), c.$1.toDouble());
    }
    if (t >= 1) {
      final c = trail.last;
      return Offset(c.$2.toDouble(), c.$1.toDouble());
    }
    final scaled = t * (trail.length - 1);
    final lowerIdx = scaled.floor();
    final upperIdx = (lowerIdx + 1).clamp(0, trail.length - 1);
    final frac = scaled - lowerIdx;
    final a = trail[lowerIdx];
    final b = trail[upperIdx];
    return Offset(
      a.$2 + (b.$2 - a.$2) * frac,
      a.$1 + (b.$1 - a.$1) * frac,
    );
  }

  @override
  void dispose() {
    _ac?.stop();
    _ac?.dispose();
    _overrides.clear();
    super.dispose();
  }
}
